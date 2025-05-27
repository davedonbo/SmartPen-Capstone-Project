import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class RssiIcon extends StatelessWidget {
  final int? rssi;
  const RssiIcon({required this.rssi});

  @override
  Widget build(BuildContext context) {
    var bars = [
      "images/bar_0.png",
      "images/bar_1.png",   //  from material icon pack
      "images/bar_2.png",
      "images/bar_3.png",
      "images/bar_4.png",
    ];
    int idx;
    if (rssi == null)       idx = 0;
    else if (rssi! >= -60)   idx = 4;   // excellent
    else if (rssi! >= -70)   idx = 3;   // good
    else if (rssi! >= -80)   idx = 2;   // fair
    else if (rssi! >= -90)   idx = 1;   // poor
    else                    idx = 0;   // very poor / out of range
    return Image.asset(bars[idx],width: 30,height: 30, color: Colors.white,);
  }
}
