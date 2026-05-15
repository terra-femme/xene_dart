import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'channel_models.dart';

/// EDUCATIONAL DEEP DIVE: ANIMATEDSWITCHER
/// [AnimatedSwitcher] is one of Flutter's most powerful native widgets.
/// It automatically detects when its "child" has changed (via a Key)
/// and runs a transition between the old child and the new one.

class ChannelFeedWrapper extends ConsumerWidget {
  const ChannelFeedWrapper({super.key, required this.builder});

  /// A function that returns the list of cards for a given channel.
  final Widget Function(Channel channel) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeChannel = ref.watch(activeChannelProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      
      /// GPU EDUCATION: TRANSITION BUILDER
      /// To optimize performance (especially during auto-scroll), 
      /// we use the "Sweep" style:
      /// 1. Incoming child slides in from the right.
      /// 2. Outgoing child fades out stationary to reduce GPU load.
      transitionBuilder: (Widget child, Animation<double> animation) {
        final activeChannel = ref.read(activeChannelProvider);
        final isIncoming = child.key == ValueKey(activeChannel.id);

        if (isIncoming) {
          // Slide + Fade for the NEW content
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        } else {
          // Just Fade for the OLD content (Stay stationary horizontally)
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        }
      },
      
      /// IMPORTANT: The KeyedSubtree tells AnimatedSwitcher that 
      /// the content has changed and it's time to animate.
      child: KeyedSubtree(
        key: ValueKey(activeChannel.id),
        child: builder(activeChannel),
      ),
    );
  }
}
