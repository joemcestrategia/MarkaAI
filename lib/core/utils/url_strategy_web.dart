// Web implementation that forwards to flutter_web_plugins.
import 'package:flutter_web_plugins/url_strategy.dart';

void configurePathUrlStrategy() {
  setUrlStrategy(PathUrlStrategy());
}

