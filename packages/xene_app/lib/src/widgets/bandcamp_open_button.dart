import 'package:flutter/material.dart';

const bandcampButtonAsset = 'assets/bandcamp-button-bc-circle-green-64.png';

class BandcampOpenButton extends StatelessWidget {
  const BandcampOpenButton({super.key, required this.onTap, this.size = 64});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open in Bandcamp',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Image.asset(
            bandcampButtonAsset,
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
