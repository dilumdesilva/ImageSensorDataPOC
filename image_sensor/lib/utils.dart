import 'package:flutter/material.dart';

bool isPortraitMode(BuildContext context) =>
    MediaQuery.of(context).orientation == Orientation.portrait;
