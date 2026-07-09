import 'dart:html' as html;
import 'dart:js' as js;

bool isPwaStandalone() {
  try {
    final mediaQuery = html.window.matchMedia('(display-mode: standalone)');
    bool isSafariStandalone = false;
    if (js.context.hasProperty('navigator')) {
      final nav = js.context['navigator'];
      if (nav != null && nav.hasProperty('standalone')) {
        isSafariStandalone = nav['standalone'] == true;
      }
    }
    return mediaQuery.matches || isSafariStandalone;
  } catch (e) {
    return false;
  }
}
