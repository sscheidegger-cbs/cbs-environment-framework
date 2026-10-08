import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes the CBS Flutter UX public contract', () {
    expect(CbsFlutterUx.packageName, 'cbs_flutter_ux');
  });
}
