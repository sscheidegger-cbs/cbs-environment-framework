import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

class ContentCardSection extends StatelessWidget {
  const ContentCardSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CbsContentCard(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Generic content', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Presentation supplied by the consuming application.'),
            ],
          ),
          media: SizedBox(height: 72, child: ColoredBox(
            color: Colors.black12,
            child: Center(child: Icon(Icons.image_outlined)),
          )),
        ),
        const SizedBox(height: 12),
        const CbsContentCard(
          layout: CbsContentCardLayout.horizontal,
          content: Text('Horizontal content'),
          media: SizedBox(width: 72, height: 72, child: Icon(Icons.image_outlined)),
        ),
      ],
    );
  }
}
