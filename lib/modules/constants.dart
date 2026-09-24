const String appName = 'JA LAN Messenger';
const String appVersion = '1.4.0';
const String appId = 'com.jatech.lan_messenger';

// Mạng P2P & Cổng mặc định (Đối chiếu BeeBEEP)
const int defaultBroadcastPort = 36475;
const int defaultListenerPort = 6475;
const int defaultFileTransferPort = 6476;

const String defaultMulticastGroup = '224.0.64.75';
const String defaultBroadcastAddress = '255.255.255.255';

// Kích thước cửa sổ nhỏ gọn, nhẹ, linh hoạt
const double defaultWindowWidth = 960.0;
const double defaultWindowHeight = 640.0;
const double minWindowWidth = 720.0;
const double minWindowHeight = 480.0;

// Kích thước cửa sổ chế độ thu nhỏ (Compact Mode góc màn hình)
const double defaultCompactWidth = 340.0;
const double defaultCompactHeight = 560.0;
const double minCompactWidth = 320.0;
const double minCompactHeight = 420.0;

// Reject standard-window geometry accidentally saved as compact geometry.
double restoredCompactWidth(double? width) =>
    width == null || !width.isFinite || width >= minWindowWidth
    ? defaultCompactWidth
    : width.clamp(minCompactWidth, minWindowWidth).toDouble();

double restoredCompactHeight(double? width, double? height) =>
    width == null ||
        !width.isFinite ||
        width >= minWindowWidth ||
        height == null ||
        !height.isFinite
    ? defaultCompactHeight
    : height.clamp(minCompactHeight, double.infinity).toDouble();
