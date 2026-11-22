import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_platform.dart';
import 'bill_share_card.dart';

enum ShareCardOutcome { shared, failed, unavailable }

Future<Uint8List> renderBillShareCardPng(
  RenderRepaintBoundary boundary, {
  required double devicePixelRatio,
}) async {
  final size = boundary.size;
  if (size.isEmpty) throw StateError('Share card has no size');
  final desiredRatio = math.max(3.0, devicePixelRatio);
  const maxDimension = 32768.0;
  const maxPixels = 24000000.0;
  final dimensionRatio = maxDimension / math.max(size.width, size.height);
  final areaRatio = math.sqrt(maxPixels / (size.width * size.height));
  final pixelRatio = math.min(
    desiredRatio,
    math.min(dimensionRatio, areaRatio),
  );
  if (pixelRatio < 1) {
    throw StateError('Share card is too large to render safely');
  }

  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes == 0) {
      throw StateError('PNG encoding returned no bytes');
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<void> shareBillCard(BuildContext context, ShareBillCardData data) async {
  final outcome = await Navigator.of(context).push<ShareCardOutcome>(
    MaterialPageRoute(builder: (_) => _ShareCardExportScreen(data: data)),
  );
  if (!context.mounted ||
      outcome == null ||
      outcome == ShareCardOutcome.shared) {
    return;
  }
  final message = outcome == ShareCardOutcome.unavailable
      ? 'No compatible app could open the share sheet.'
      : 'The bill image could not be prepared. Try sharing again.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _ShareCardExportScreen extends StatefulWidget {
  const _ShareCardExportScreen({required this.data});

  final ShareBillCardData data;

  @override
  State<_ShareCardExportScreen> createState() => _ShareCardExportScreenState();
}

class _ShareCardExportScreenState extends State<_ShareCardExportScreen> {
  final _boundary = GlobalKey();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _waitForRouteTransition();
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) await _export();
    });
  }

  Future<void> _waitForRouteTransition() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null ||
        animation.status == AnimationStatus.completed ||
        animation.status == AnimationStatus.dismissed) {
      return;
    }
    final settled = Completer<void>();
    late AnimationStatusListener listener;
    listener = (status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        animation.removeStatusListener(listener);
        settled.complete();
      }
    };
    animation.addStatusListener(listener);
    await settled.future;
  }

  Future<void> _export() async {
    try {
      final renderObject = _boundary.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('Share card was not painted');
      }
      final png = await renderBillShareCardPng(
        renderObject,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      await AppPlatform.sharePng(png);
      if (mounted) Navigator.of(context).pop(ShareCardOutcome.shared);
    } on PlatformException catch (error) {
      if (mounted) {
        Navigator.of(context).pop(
          error.code == 'SHARE_UNAVAILABLE'
              ? ShareCardOutcome.unavailable
              : ShareCardOutcome.failed,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Bill share preparation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Navigator.of(context).pop(ShareCardOutcome.failed);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Preparing share card')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: RepaintBoundary(
              key: _boundary,
              child: ShareBillCard(data: widget.data),
            ),
          ),
        ),
      ),
    ),
  );
}
