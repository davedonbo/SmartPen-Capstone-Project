#include <Arduino_LSM9DS1.h>
#include <ArduinoBLE.h>
#include <Chirale_TensorFlowLite.h>
#include "model_nac.h"
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/schema/schema_generated.h"
#include <math.h>

/* ───── USER‑TUNABLE CONSTANTS (compile‑time) ─────────────────────────── */
#define ODR_HZ                 59.5f   // IMU output‑data‑rate (Hz)
#define BUF_LEN                150     // circular buffer length (samples)
#define FEATURES               6       // ax, ay, az, gx, gy, gz
#define ACT_WINDOW             10      // samples in Δ‑mag window
#define THRESH_STD_DEV         130.0f   // Standard deviation threshold (mg)
#define THRESH_STD_DEV_STP     35.0f   // Standard deviation threshold (mg)
#define QUIET_SAMPLES          6       // successive quiet samples = capture end
#define PRE_ROLL               10      // prepend silent samples
#define POST_ROLL              0       // append silent samples
/* 15 s × 59.5 Hz ≈ 893 samples */
#define SLEEP_QUIET_SAMPLES    893  

// ───── BLE UUIDs ──────────────────────────────────────────────────────────
#define SERVICE_UUID        "19B10000-E8F2-537E-4F6C-D104768A1214"
#define CHARACTERISTIC_UUID "19B10001-E8F2-537E-4F6C-D104768A1214"
#define COMMAND_UUID        "19B10002-E8F2-537E-4F6C-D104768A1214"

// BLE objects
BLEService sensorService(SERVICE_UUID);
BLEStringCharacteristic dataCharacteristic(CHARACTERISTIC_UUID, BLERead | BLENotify, 128);
BLECharCharacteristic commandCharacteristic(COMMAND_UUID, BLERead | BLEWrite);

bool enable_sleep = 0;

// ───── States ─────────────────────────────────────────────────────────────
bool collecting = false;

// ───── Model / Buffer sizes ───────────────────────────────────────────────
const int kTimeSteps = 64;
const int kFeatures = 6; // ax, ay, az, gx, gy, gz
const int kClasses = 27;
const int MAX_RAW_SAMPLES = 150;
const int MIN_SAMPLES_NEEDED = kTimeSteps;

float raw_samples[MAX_RAW_SAMPLES][kFeatures];
int sample_count = 0;

// ───── TFLM globals ───────────────────────────────────────────────────────
namespace {
  const tflite::Model* model = nullptr;
  tflite::MicroInterpreter* interpreter = nullptr;
  TfLiteTensor* input = nullptr;
  TfLiteTensor* output = nullptr;

  constexpr int kTensorArenaSize = 16 * 1024;
  uint8_t tensor_arena[kTensorArenaSize];
}

// ───────── Buffer & FSM Setup ─────────────────────────────────────────
struct Frame { float v[kFeatures]; };
static Frame     ring[BUF_LEN];
static uint16_t  ringMag[BUF_LEN];
static uint16_t  head = 0;
static uint32_t  quietStreak = 0;

// ───── Utility functions ──────────────────────────────────────────────────
void resample_to_64(const float in[][kFeatures], int len,
                    float out[kTimeSteps][kFeatures]) {
  for (int f = 0; f < kFeatures; ++f) {
    for (int i = 0; i < kTimeSteps; ++i) {
      float x = ((float)i / (kTimeSteps - 1)) * len;
      int x0 = (int)x;
      x0 = min(x0, len - 1);
      int x1 = min(x0 + 1, len - 1);
      float w = x - x0;
      out[i][f] = (1.0f - w) * in[x0][f] + w * in[x1][f];
    }
  }
}

void movingAverageFilter(float sample[kTimeSteps][kFeatures],
                         uint8_t windowSize = 5)
{
  if (windowSize == 0) return;                      

  const float norm = 1.0f / windowSize;          
  const int   half = (windowSize - 1) >> 1;        

  float column[kTimeSteps];                      

  for (int f = 0; f < kFeatures; ++f)
  {
    /* -------- copy current feature column to scratch -------- */
    for (int t = 0; t < kTimeSteps; ++t)
      column[t] = sample[t][f];

    /* -------- FIR convolution with zero padding ------------- */
    for (int t = 0; t < kTimeSteps; ++t)
    {
      float acc = 0.0f;

      /* slide through the W-point window */
      for (int k = 0; k < windowSize; ++k)
      {
        int idx = t + k - half;                   

        if (idx >= 0 && idx < kTimeSteps)        
          acc += column[idx];
      }
      sample[t][f] = acc * norm;            
    }
  }
}

int8_t quantize(float value, float scale, int zero_point) {
  float scaled = value / scale + zero_point;
  float rounded;
  if (scaled >= 0.0f) {
    rounded = floorf(scaled + 0.5f);
    if ((scaled + 0.5f - rounded) == 0.0f && fmodf(rounded, 2.0f) != 0.0f)
      rounded -= 1.0f;
  } else {
    rounded = ceilf(scaled - 0.5f);
    if ((scaled - 0.5f - rounded) == 0.0f && fmodf(rounded, 2.0f) != 0.0f)
      rounded += 1.0f;
  }
  return (int8_t)((int32_t)rounded & 0xFF);
}

void goToSleep() {
  BLE.stopAdvertise();
  BLE.disconnect();
  delay(50);

  /* nRF52840 deep sleep */
  NRF_POWER->SYSTEMOFF = 1;
  while (1) {}
}

/* Ring‑buffer helpers --------------------------------------------------- */
inline uint16_t wrap(uint16_t idx) { return (idx + BUF_LEN) % BUF_LEN; }

void standardise(float sample[kTimeSteps][kFeatures]) {
  float mu[kFeatures] = {0};
  float sigma[kFeatures] = {0};
  const float eps = 1e-8f;

  for (int f = 0; f < kFeatures; ++f) {
    for (int t = 0; t < kTimeSteps; ++t) mu[f] += sample[t][f];
    mu[f] /= kTimeSteps;
  }
  for (int f = 0; f < kFeatures; ++f) {
    for (int t = 0; t < kTimeSteps; ++t) {
      float d = sample[t][f] - mu[f];
      sigma[f] += d * d;
    }
    sigma[f] = sqrtf(sigma[f] / (kTimeSteps - 1));
  }
  for (int f = 0; f < kFeatures; ++f) {
    float inv = 1.0f / (sigma[f] + eps);
    for (int t = 0; t < kTimeSteps; ++t)
      sample[t][f] = (sample[t][f] - mu[f]) * inv;
  }
}

void sendMsg(const char* s) {
  dataCharacteristic.writeValue(String(s)+"\n");
  Serial.println(s);
}

// ───── BLE command handler ────────────────────────────────────────────────
void onCommandWritten(BLEDevice /*central*/, BLECharacteristic /*c*/) {
  if (!collecting) {
    collecting = true;
    sample_count = 0;
    dataCharacteristic.writeValue(">>>STARTED");
    return;
  }

  collecting = false;
  dataCharacteristic.writeValue(">>>STOPPED");

  if (sample_count < MIN_SAMPLES_NEEDED) {
    char msg[32];
    sprintf(msg, "Need %d, got %d", MIN_SAMPLES_NEEDED, sample_count);
    dataCharacteristic.writeValue(msg);
    return;
  }

  float seq64[kTimeSteps][kFeatures];
  resample_to_64(raw_samples, sample_count, seq64);
  standardise(seq64);

  if (input->type == kTfLiteInt8) {
    float s = input->params.scale;
    int zp = input->params.zero_point;
    int idx = 0;
    for (int t = 0; t < kTimeSteps; ++t)
      for (int f = 0; f < kFeatures; ++f)
        input->data.int8[idx++] = quantize(seq64[t][f], s, zp);
  } else {
    int idx = 0;
    for (int t = 0; t < kTimeSteps; ++t)
      for (int f = 0; f < kFeatures; ++f)
        input->data.f[idx++] = seq64[t][f];
  }

  interpreter->Invoke();

  float scores[kClasses];
  if (output->type == kTfLiteInt8) {
    float s = output->params.scale;
    int zp = output->params.zero_point;
    for (int i = 0; i < kClasses; ++i)
      scores[i] = (output->data.int8[i] - zp) * s;
  } else {
    for (int i = 0; i < kClasses; ++i)
      scores[i] = output->data.f[i];
  }

  int best = 0;
  float bestVal = scores[0];
  for (int i = 1; i < kClasses; ++i)
    if (scores[i] > bestVal) { bestVal = scores[i]; best = i; }

  char res[64];
  sprintf(res, "Predicted:%c Conf:%.4f", 'A' + best, bestVal);
  dataCharacteristic.writeValue(res);
}

enum State { WAIT_MOV, COLLECT } state = WAIT_MOV;
static uint16_t capStart = 0; 
static uint32_t capLen = 0; 
static uint32_t quietCnt = 0;
static float captureBuf[BUF_LEN][kFeatures];

// Variance calculation variables
static uint16_t magWindow[ACT_WINDOW] = {0};
static uint8_t magWindowIdx = 0;
static uint32_t sumMag = 0;
static uint32_t sumMagSq = 0;
static bool windowFilled = false;

// ───── setup() ────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);

  if (!IMU.begin()) while (1);
  if (!BLE.begin()) while (1);

  pinMode(LED_BUILTIN, OUTPUT);

  BLE.setConnectionInterval(6, 100000);
  BLE.setLocalName("SmartPen");
  BLE.setAdvertisedService(sensorService);
  sensorService.addCharacteristic(dataCharacteristic);
  sensorService.addCharacteristic(commandCharacteristic);
  BLE.addService(sensorService);

  dataCharacteristic.writeValue(">>>READY");
  commandCharacteristic.writeValue(0);
  commandCharacteristic.setEventHandler(BLEWritten, onCommandWritten);
  BLE.advertise();

  model = tflite::GetModel(model_tflite);
  static tflite::AllOpsResolver resolver;
  static tflite::MicroInterpreter staticInterp(
      model, resolver, tensor_arena, kTensorArenaSize
  );
  interpreter = &staticInterp;
  if (interpreter->AllocateTensors() != kTfLiteOk) while (1);
  input = interpreter->input(0);
  output = interpreter->output(0);

  sendMsg("INFO: WAKE");
}

// ───── loop() ─────────────────────────────────────────────────────────────
void loop() {
  BLE.poll();
  digitalWrite(LED_BUILTIN, BLE.connected());

  // IMU Data Acquisition
  float ax, ay, az, gx, gy, gz;
  if (!IMU.accelerationAvailable() && !IMU.gyroscopeAvailable()) return;
  IMU.readAcceleration(ax, ay, az);
  IMU.readGyroscope(gx, gy, gz);
  
  // Update Ring Buffer
  uint16_t mag = (uint16_t)(fabs(ax)*1000 + fabs(ay)*1000 + fabs(az)*1000);
  head = wrap(head + 1);
  ring[head] = {ax, ay, az, gx, gy, gz};
  ringMag[head] = mag;

  // Update variance window
  if (windowFilled) {
    uint16_t oldestMag = magWindow[magWindowIdx];
    sumMag -= oldestMag;
    sumMagSq -= (uint32_t)oldestMag * oldestMag;
  }

  magWindow[magWindowIdx] = mag;
  sumMag += mag;
  sumMagSq += (uint32_t)mag * mag;

  magWindowIdx = (magWindowIdx + 1) % ACT_WINDOW;
  windowFilled = windowFilled || (magWindowIdx == 0);

  // Calculate standard deviation
  float stdDev = 0.0f;
  if (windowFilled || magWindowIdx >= 2) {
    uint16_t n = windowFilled ? ACT_WINDOW : magWindowIdx;
    float mean = (float)sumMag / n;
    float variance = ((float)sumMagSq - (sumMag * sumMag) / n) / (n - 1);
    stdDev = sqrt(variance);
  }

  switch(state) {
    case WAIT_MOV:
      if (stdDev >= THRESH_STD_DEV) {
        capStart = wrap(head - PRE_ROLL);
        capLen = PRE_ROLL + 1;
        quietCnt = 0;
        state = COLLECT;
        sendMsg("STATUS:COLLECTING");
      } else {
        quietStreak++;
        if(quietStreak>=SLEEP_QUIET_SAMPLES && enable_sleep){
          sendMsg("INFO:SLEEP");
          goToSleep();
        }
      }
      break;

    case COLLECT:
      capLen++;
      quietCnt = (stdDev < THRESH_STD_DEV_STP) ? quietCnt + 1 : 0;
      
      if (quietCnt >= QUIET_SAMPLES) {
        capLen += POST_ROLL;
        if (capLen <= BUF_LEN) {
          uint16_t idx = capStart;
          for (uint32_t i = 0; i < capLen; i++) {
            memcpy(captureBuf[i], ring[idx].v, sizeof(ring[idx].v));
            idx = wrap(idx + 1);
          }
          
          float seq64[kTimeSteps][kFeatures];
          resample_to_64(captureBuf, capLen, seq64);
          movingAverageFilter(seq64, 5);
          standardise(seq64);

          if (input->type == kTfLiteInt8) {
            float scale = input->params.scale;
            int zero_point = input->params.zero_point;
            int k = 0;
            for (int t = 0; t < kTimeSteps; t++) {
              for (int f = 0; f < kFeatures; f++, k++) {
                input->data.int8[k] = quantize(seq64[t][f], scale, zero_point);
              }
            }
          } else {
            memcpy(input->data.f, seq64, sizeof(seq64));
          }

          TfLiteStatus invokeStatus = interpreter->Invoke();
          if (invokeStatus != kTfLiteOk) {
            sendMsg("ERR:INFERENCE");
          } else {
            auto score = [&](int i) {
              return (output->type == kTfLiteInt8) 
                ? (output->data.int8[i] - output->params.zero_point) * output->params.scale
                : output->data.f[i];
            };
            
            int best = 0;
            float prob = score(0);
            for (int i = 1; i < output->dims->data[1]; i++) {
              float s = score(i);
              if (s > prob) {
                prob = s;
                best = i;
              }
            }
            
          char result[64];
          char letter = (best >= 0 && best < 26) ? ('A' + best) : '?';
          snprintf(result, sizeof(result), "PRED:%c,%d, LEN:%d", letter, (int)(prob * 100),capLen);
          sendMsg(result);
          }
        } else {
          sendMsg("WARN:CAPTURE_TOO_LONG");
        }
        state = WAIT_MOV;
        quietStreak = 0;
      } else if (capLen >= BUF_LEN) {
        sendMsg("WARN:CAPTURE_OVERFLOW");
        state = WAIT_MOV;
        quietStreak = 0;
      }
      break;
  }
}