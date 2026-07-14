import Foundation
import Combine

// MARK: - 接続方式
enum WanType: String, CaseIterable, Identifiable {
    case pppoe = "PPPoE (フレッツ等)"
    case dhcp  = "DHCP (自動取得)"
    case staticIP = "固定IP (NURO Biz等)"
    case ipoe = "IPoE (IPv4 over IPv6)"
    var id: String { rawValue }
}

// MARK: - IPoE方式
enum IPoEMethod: String, CaseIterable, Identifiable {
    case dsLite = "DS-Lite"
    case mapE   = "MAP-E"
    var id: String { rawValue }
}

// DS-Lite プロバイダ (AFTRアドレス)
enum DsLiteProvider: String, CaseIterable, Identifiable {
    case transixEast = "transix (東日本)"
    case transixWest = "transix (西日本)"
    case xpass       = "クロスパス (xpass)"
    case v6connect   = "v6コネクト"
    var id: String { rawValue }
    var aftr: String {
        switch self {
        case .transixEast: return "2404:8e00::feed:100"
        case .transixWest: return "2404:8e01::feed:100"
        case .xpass:       return "dgw.xpass.jp"
        case .v6connect:   return "dslite.v6connect.net"
        }
    }
}

// MAP-E プロバイダ
enum MapEProvider: String, CaseIterable, Identifiable {
    case v6plus = "v6プラス"
    case ocn    = "OCNバーチャルコネクト"
    var id: String { rawValue }
    var mapEType: String {
        switch self {
        case .v6plus: return "v6plus"
        case .ocn:    return "ocn"
        }
    }
}

// MARK: - ポート開放エントリ
struct PortForward: Identifiable, Equatable {
    let id = UUID()
    var proto: String = "tcp"       // tcp / udp
    var port: String = "80"         // 外部/内部ポート (同一)
    var innerIP: String = "192.168.100.2"
    var memo: String = ""
}

// MARK: - VPN方式
enum VpnMode: String, CaseIterable, Identifiable {
    case main    = "固定IP相互 (メインモード)"
    case center  = "センター側 (相手が動的IP)"
    case branch  = "拠点側 (自分が動的IP)"
    var id: String { rawValue }
}

// MARK: - 拠点間VPNトンネル
struct VpnTunnel: Identifiable, Equatable {
    let id = UUID()
    var memo: String = "拠点1"
    var mode: VpnMode = .main
    var peerAddress: String = ""      // 相手グローバルIP (main / branch)
    var peerName: String = ""         // 相手識別名 (center)
    var localName: String = ""        // 自分の識別名 (branch)
    var psk: String = ""              // 事前共有鍵
    var remoteLan: String = "192.168.200.0/24"  // 相手側LAN
}

// MARK: - VPN暗号強度
enum VpnStrength: String, CaseIterable, Identifiable {
    case strong = "推奨 (AES256 / SHA256 / DH14)"
    case compat = "互換 (AES / SHA1 / DH2)"
    var id: String { rawValue }
}

// MARK: - リモートアクセスユーザー
struct RemoteUser: Identifiable, Equatable {
    let id = UUID()
    var name: String = ""
    var password: String = ""
}

// MARK: - 設定モデル
final class ConfigModel: ObservableObject {

    // セクション有効フラグ (カテゴリのチェック / 外すとその範囲を出力しない)
    @Published var secBasic: Bool = true
    @Published var secLan: Bool = true
    @Published var secWan: Bool = true
    @Published var secDns: Bool = true
    @Published var secPortForward: Bool = true
    @Published var secMgmt: Bool = true
    @Published var secSyslog: Bool = true

    // 基本
    @Published var memoTitle: String = "RTX1220"
    @Published var consoleUTF8: Bool = true
    @Published var loginTimeout: Double = 300     // 秒
    @Published var adminPassword: String = ""
    @Published var loginUser: String = ""       // ログインユーザー名 (login user)
    @Published var loginPassword: String = ""

    // LAN1
    @Published var lan1Address: String = "192.168.100.1"
    @Published var lan1Prefix: Double = 24

    // WAN
    @Published var wanType: WanType = .pppoe
    @Published var pppoeUser: String = ""
    @Published var pppoePass: String = ""
    @Published var pppoeAlwaysOn: Bool = true
    @Published var staticWanIP: String = "203.0.113.2"
    @Published var staticWanPrefix: Double = 29
    @Published var staticWanGateway: String = "203.0.113.1"
    @Published var mtu: Double = 1454

    // IPoE
    @Published var ipoeMethod: IPoEMethod = .dsLite
    @Published var dsLiteProvider: DsLiteProvider = .transixEast
    @Published var aftrOverride: String = ""       // 空ならプロバイダ既定値
    @Published var mapEProvider: MapEProvider = .v6plus
    @Published var distributeIPv6: Bool = true      // LAN側へIPv6を配布

    // DHCP
    @Published var dhcpEnabled: Bool = true
    @Published var dhcpStart: String = "192.168.100.2"
    @Published var dhcpEnd: String = "192.168.100.191"
    @Published var dhcpLeaseHours: Double = 72

    // DNS
    @Published var dnsFromProvider: Bool = true      // ISPから自動取得
    @Published var dnsServers: String = "8.8.8.8 8.8.4.4"
    @Published var dnsRecursive: Bool = true

    // NAT
    @Published var naptEnabled: Bool = true

    // ポート開放
    @Published var portForwards: [PortForward] = []

    // 拠点間VPN (IPsec)
    @Published var vpnEnabled: Bool = false
    @Published var vpnStrength: VpnStrength = .strong
    @Published var vpnTunnels: [VpnTunnel] = []

    // リモートアクセスVPN (L2TP/IPsec)
    @Published var remoteEnabled: Bool = false
    @Published var remotePSK: String = ""
    @Published var remoteUsers: [RemoteUser] = [RemoteUser(name: "vpnuser", password: "")]
    @Published var remotePoolStart: String = "192.168.100.201"
    @Published var remotePoolEnd: String = "192.168.100.210"

    // セキュリティ / フィルタ
    @Published var useSecurityFilter: Bool = true
    @Published var passICMP: Bool = true

    // 管理アクセス
    @Published var enableTelnet: Bool = false
    @Published var enableSSH: Bool = true
    @Published var enableHTTP: Bool = true
    @Published var blockWanAdmin: Bool = true        // WAN側からの管理アクセス拒否

    // NTP
    @Published var ntpEnabled: Bool = true
    @Published var ntpServer: String = "ntp.nict.jp"

    // Syslog
    @Published var syslogHost: String = ""
    @Published var syslogNotice: Bool = true
    @Published var syslogInfo: Bool = false
    @Published var syslogDebug: Bool = false
}
