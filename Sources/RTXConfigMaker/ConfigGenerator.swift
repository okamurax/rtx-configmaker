import Foundation

// RTX1220 用コンフィグ生成
enum ConfigGenerator {

    /// "192.168.100.1" と prefix 24 から "192.168.100.0/24" を求める
    static func networkAddress(ip: String, prefix: Int) -> String? {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4, prefix >= 0, prefix <= 32 else { return nil }
        var value: UInt32 = 0
        for p in parts { value = (value << 8) | UInt32(p) }
        let mask: UInt32 = prefix == 0 ? 0 : (~UInt32(0) << (32 - prefix))
        let net = value & mask
        let a = (net >> 24) & 0xff, b = (net >> 16) & 0xff, c = (net >> 8) & 0xff, d = net & 0xff
        return "\(a).\(b).\(c).\(d)/\(prefix)"
    }

    static func generate(_ m: ConfigModel) -> String {
        var L: [String] = []
        func add(_ s: String = "") { L.append(s) }

        let prefix = Int(m.lan1Prefix)
        let lanNet = networkAddress(ip: m.lan1Address, prefix: prefix) ?? "192.168.100.0/24"
        let mtu = Int(m.mtu)
        let natDesc = 1000

        // IPoEがtunnel 1を使うか (WANセクション有効かつIPoE時)
        let ipoeUsesTunnel1 = (m.wanType == .ipoe) && m.secWan
        let vpnBase = ipoeUsesTunnel1 ? 1 : 0
        let activeVpn = m.vpnEnabled ? m.vpnTunnels.filter { !$0.psk.isEmpty && !$0.remoteLan.isEmpty } : []
        let ipsecInbound = (!activeVpn.isEmpty) || m.remoteEnabled   // ESP/IKEをWANで通す必要があるか

        // ---- ヘッダ ----
        add("# ==============================================")
        add("# \(m.memoTitle)")
        add("# RTX1220 config  (RTX ConfigMaker で生成)")
        add("# 接続方式: \(m.wanType.rawValue)")
        add("# ==============================================")
        add()

        // ---- 基本 ----
        if m.secBasic {
            if m.consoleUTF8 { add("console character ja.utf8") }
            add("console lines infinity")
            add("login timeout \(Int(m.loginTimeout))")
            if !m.loginUser.isEmpty {
                add("login user \(m.loginUser) \(m.loginPassword.isEmpty ? "パスワード" : m.loginPassword)")
            }
            add()
        }

        // ---- LAN1 ----
        if m.secLan {
            add("# --- LAN1 (内部ネットワーク) ---")
            add("ip lan1 address \(m.lan1Address)/\(prefix)")
            add()
        }

        // ---- WAN / ルーティング ----
        if m.secWan {
        add("# --- インターネット接続 (WAN / LAN2) ---")
        switch m.wanType {
        case .pppoe:
            add("ip route default gateway pp 1")
            add("pp select 1")
            add(" pp always-on \(m.pppoeAlwaysOn ? "on" : "off")")
            add(" pppoe use lan2")
            add(" pppoe auto disconnect off")
            add(" pp auth accept pap chap")
            add(" pp auth myname \(m.pppoeUser.isEmpty ? "PPPoEユーザー名" : m.pppoeUser) \(m.pppoePass.isEmpty ? "PPPoEパスワード" : m.pppoePass)")
            add(" ppp lcp mru on \(mtu)")
            add(" ppp ipcp msext on")
            add(" ppp ipcp ipaddress on")
            add(" ppp ccp type none")
            add(" ip pp mtu \(mtu)")
            if m.naptEnabled { add(" ip pp nat descriptor \(natDesc)") }
            if m.useSecurityFilter {
                add(" ip pp secure filter in \(inFilterList(m))")
                add(" ip pp secure filter out \(outFilterList())")
            }
            add(" pp enable 1")
        case .dhcp:
            add("ip lan2 address dhcp")
            add("ip route default gateway dhcp lan2")
            if m.naptEnabled { add("ip lan2 nat descriptor \(natDesc)") }
            if m.useSecurityFilter {
                add("ip lan2 secure filter in \(inFilterList(m))")
                add("ip lan2 secure filter out \(outFilterList())")
            }
        case .staticIP:
            let wanPrefix = Int(m.staticWanPrefix)
            add("ip lan2 address \(m.staticWanIP)/\(wanPrefix)")
            add("ip route default gateway \(m.staticWanGateway)")
            if m.naptEnabled { add("ip lan2 nat descriptor \(natDesc)") }
            if m.useSecurityFilter {
                add("ip lan2 secure filter in \(inFilterList(m))")
                add("ip lan2 secure filter out \(outFilterList())")
            }
        case .ipoe:
            // --- IPv6 (IPoE / NGN) ---
            add("# IPv6 (IPoE / NGN網)")
            add("ipv6 lan2 address dhcp")
            add("ipv6 lan2 dhcp service client ir=on")
            add("ipv6 route default gateway dhcp lan2")
            if m.distributeIPv6 {
                add("ipv6 prefix 1 ra-prefix@lan2::/64")
                add("ipv6 lan1 address ra-prefix@lan2::1/64")
                add("ipv6 lan1 rtadv send 1 o_flag=on")
                add("ipv6 lan1 dhcp service server")
            }
            if m.useSecurityFilter {
                add("ipv6 lan2 secure filter in \(ipv6InList())")
                add("ipv6 lan2 secure filter out \(ipv6OutList())")
            }
            // --- IPv4 (トンネル) ---
            add("# IPv4 (\(m.ipoeMethod.rawValue) トンネル)")
            add("ip route default gateway tunnel 1")
            add("tunnel select 1")
            switch m.ipoeMethod {
            case .dsLite:
                let aftr = m.aftrOverride.isEmpty ? m.dsLiteProvider.aftr : m.aftrOverride
                add(" tunnel encapsulation ipip")
                if aftr.contains(":") {
                    add(" tunnel endpoint address \(aftr)")   // AFTRをIPv6アドレスで指定
                } else {
                    add(" tunnel endpoint name \(aftr)")       // AFTRをFQDNで指定
                }
            case .mapE:
                add(" tunnel encapsulation map-e")
                add(" tunnel map-e type \(m.mapEProvider.mapEType)")
                add(" # ※map-e対応はファーム Rev.15.04系。type名はご契約サービスに合わせて確認")
            }
            add(" ip tunnel mtu 1460")
            add(" ip tunnel tcp mss limit auto")
            if m.ipoeMethod == .mapE && m.naptEnabled {
                add(" ip tunnel nat descriptor \(natDesc)")
            }
            if m.useSecurityFilter {
                add(" ip tunnel secure filter in \(inFilterList(m))")
                add(" ip tunnel secure filter out \(outFilterList())")
            }
            add(" tunnel enable 1")
        }
        add()
        }  // end secWan

        // ---- NAT / IPマスカレード ----
        // DS-Lite はRTX側でNATしない (AFTR側でNAT44)
        let dsLite = (m.wanType == .ipoe && m.ipoeMethod == .dsLite)
        let mapE = (m.wanType == .ipoe && m.ipoeMethod == .mapE)
        if m.naptEnabled && !dsLite {
            add("# --- NAT / IPマスカレード ---")
            add("nat descriptor type \(natDesc) masquerade")
            switch m.wanType {
            case .pppoe:    add("nat descriptor address outer \(natDesc) ipcp")
            case .dhcp:     add("nat descriptor address outer \(natDesc) primary")
            case .staticIP: add("nat descriptor address outer \(natDesc) \(m.staticWanIP)")
            case .ipoe:     add("nat descriptor address outer \(natDesc) map-e")
            }
            add("nat descriptor address inner \(natDesc) auto")
            if mapE {
                add("# MAP-Eの利用可能ポート範囲はMAP-Eルールで自動決定されます")
                add("# (ポート開放は割当てられた範囲内のポートのみ有効)")
            }
            // ポート開放 (静的NAT)
            var staticSlot = 0
            if m.secPortForward {
                for pf in m.portForwards where !pf.innerIP.isEmpty && !pf.port.isEmpty {
                    staticSlot += 1
                    let memo = pf.memo.isEmpty ? "" : "  # \(pf.memo)"
                    add("nat descriptor masquerade static \(natDesc) \(staticSlot) \(pf.innerIP) \(pf.proto) \(pf.port)\(memo)")
                }
            }
            // リモートアクセス(L2TP/IPsec)終端をルーター自身へ振り向け
            if m.remoteEnabled {
                add("# リモートアクセスVPN終端をルーター自身へ")
                add("nat descriptor masquerade static \(natDesc) \(staticSlot + 1) \(m.lan1Address) udp 500")
                add("nat descriptor masquerade static \(natDesc) \(staticSlot + 2) \(m.lan1Address) esp")
                add("nat descriptor masquerade static \(natDesc) \(staticSlot + 3) \(m.lan1Address) udp 4500")
            }
            add()
        } else if dsLite {
            add("# --- NAT ---")
            add("# DS-LiteはRTX側でNATしません (AFTR側でNAT44処理)")
            add()
        }

        // ---- フィルタ定義 ----
        if m.useSecurityFilter {
            add("# --- 静的フィルタ定義 ---")
            add("ip filter 200003 reject \(lanNet) * * * *")
            add("ip filter 200013 reject * \(lanNet) * * *")
            add("ip filter 200020 reject * * udp,tcp 135 *")
            add("ip filter 200021 reject * * udp,tcp * 135")
            add("ip filter 200022 reject * * udp,tcp netbios_ns-netbios_ssn *")
            add("ip filter 200023 reject * * udp,tcp * netbios_ns-netbios_ssn")
            add("ip filter 200024 reject * * udp,tcp 445 *")
            add("ip filter 200025 reject * * udp,tcp * 445")
            if m.passICMP { add("ip filter 200030 pass * \(lanNet) icmp * *") }
            add("ip filter 200031 pass * \(lanNet) established * *")
            add("ip filter 200032 pass * \(lanNet) tcp * ident")
            add("ip filter 200033 pass * \(lanNet) tcp ftpdata *")
            add("ip filter 200034 pass * \(lanNet) tcp,udp * domain")
            add("ip filter 200035 pass * \(lanNet) udp domain *")
            add("ip filter 200036 pass * \(lanNet) udp * ntp")
            add("ip filter 200037 pass * \(lanNet) udp ntp *")
            // ポート開放用 pass フィルタ
            if m.secPortForward {
                for (i, pf) in m.portForwards.enumerated() where !pf.innerIP.isEmpty && !pf.port.isEmpty {
                    add("ip filter \(200040 + i) pass * \(pf.innerIP) \(pf.proto) * \(pf.port)")
                }
            }
            if ipsecInbound {
                add("# VPN (IPsec/L2TP) 通過許可")
                add("ip filter 200100 pass * * esp * *")
                add("ip filter 200101 pass * * udp * 500")
                add("ip filter 200102 pass * * udp * 4500")
            }
            add("ip filter 200099 pass * * * * *")
            add("# --- 動的フィルタ定義 (ステートフル) ---")
            add("ip filter dynamic 200080 * * ftp")
            add("ip filter dynamic 200081 * * www")
            add("ip filter dynamic 200082 * * domain")
            add("ip filter dynamic 200083 * * smtp")
            add("ip filter dynamic 200084 * * pop3")
            add("ip filter dynamic 200085 * * submission")
            add("ip filter dynamic 200098 * * tcp")
            add("ip filter dynamic 200099 * * udp")
            // IPoE時のIPv6フィルタ
            if m.wanType == .ipoe {
                add("# --- IPv6 フィルタ定義 (IPoE) ---")
                add("ipv6 filter 101000 pass * * icmp6 * *")
                add("ipv6 filter 101001 pass * * tcp * ident")
                add("ipv6 filter 101002 pass * * udp * 546")
                add("ipv6 filter 101003 pass * fe80::/10 * * *")
                add("ipv6 filter 101020 reject * * udp,tcp 135 *")
                add("ipv6 filter 101021 reject * * udp,tcp * 135")
                add("ipv6 filter 101022 reject * * udp,tcp netbios_ns-netbios_ssn *")
                add("ipv6 filter 101023 reject * * udp,tcp * netbios_ns-netbios_ssn")
                add("ipv6 filter 101024 reject * * udp,tcp 445 *")
                add("ipv6 filter 101025 reject * * udp,tcp * 445")
                add("ipv6 filter 101099 pass * * * * *")
                add("ipv6 filter dynamic 101080 * * ftp")
                add("ipv6 filter dynamic 101081 * * www")
                add("ipv6 filter dynamic 101082 * * domain")
                add("ipv6 filter dynamic 101083 * * smtp")
                add("ipv6 filter dynamic 101084 * * pop3")
                add("ipv6 filter dynamic 101085 * * submission")
                add("ipv6 filter dynamic 101098 * * tcp")
                add("ipv6 filter dynamic 101099 * * udp")
            }
            add()
        }

        // ---- 拠点間VPN (IPsec) ----
        let activeTunnels = activeVpn
        if m.vpnEnabled && !activeTunnels.isEmpty {
            add("# --- 拠点間VPN (IPsec) ---")
            let (esp, ikeEnc, ikeHash, ikeGroup): (String, String, String, String) = {
                switch m.vpnStrength {
                case .strong: return ("esp aes256-cbc sha256-hmac", "aes256-cbc", "sha256", "modp2048")
                case .compat: return ("esp aes-cbc sha-hmac", "aes-cbc", "sha", "modp1024")
                }
            }()

            // IPoEがtunnel 1を使う場合、VPNは tunnel 2 以降に採番
            let tunnelBase = vpnBase
            for (idx, t) in activeTunnels.enumerated() {
                let n = tunnelBase + idx + 1
                let policyId = 100 + n
                add("tunnel select \(n)")
                add(" description tunnel \(t.memo)")
                add(" ipsec tunnel \(n)")
                add("  ipsec sa policy \(policyId) \(n) \(esp)")
                add("  ipsec ike encryption \(n) \(ikeEnc)")
                add("  ipsec ike hash \(n) \(ikeHash)")
                add("  ipsec ike group \(n) \(ikeGroup)")
                add("  ipsec ike keepalive use \(n) on dpd")
                add("  ipsec ike nat-traversal \(n) on")
                add("  ipsec ike pre-shared-key \(n) text \(t.psk)")
                switch t.mode {
                case .main:
                    let peer = t.peerAddress.isEmpty ? "相手グローバルIP" : t.peerAddress
                    add("  ipsec ike remote address \(n) \(peer)")
                case .center:
                    let name = t.peerName.isEmpty ? "相手拠点の識別名" : t.peerName
                    add("  ipsec ike remote address \(n) any")
                    add("  ipsec ike remote name \(n) \(name) key-id")
                case .branch:
                    let peer = t.peerAddress.isEmpty ? "センターのグローバルIP" : t.peerAddress
                    let name = t.localName.isEmpty ? "自拠点の識別名" : t.localName
                    add("  ipsec ike remote address \(n) \(peer)")
                    add("  ipsec ike local name \(n) \(name) key-id")
                }
                add(" ip tunnel tcp mss limit auto")
                add(" tunnel enable \(n)")
            }
            add("ipsec auto refresh on")
            add("# 相手側LANへの経路")
            for (idx, t) in activeTunnels.enumerated() {
                add("ip route \(t.remoteLan) gateway tunnel \(tunnelBase + idx + 1)")
            }
            add()
        }

        // ---- リモートアクセスVPN (L2TP/IPsec) ----
        if m.remoteEnabled {
            let raT = vpnBase + activeVpn.count + 1      // 拠点間VPNの次の番号
            let policyId = 100 + raT
            add("# --- リモートアクセスVPN (L2TP/IPsec) ---")
            if m.wanType == .ipoe {
                add("# ※IPoE(MAP-E/DS-Lite)環境ではポート制約によりL2TP/IPsecの着信は不可/不安定です")
            }
            if activeVpn.isEmpty { add("ipsec auto refresh on") }   // 拠点間VPN側で出力済みなら省略
            add("ipsec transport \(raT) \(policyId) udp 1701")
            add("l2tp service on")
            add("tunnel select \(raT)")
            add(" tunnel encapsulation l2tp")
            add(" ipsec tunnel \(raT)")
            add("  ipsec sa policy \(policyId) \(raT) esp aes-cbc sha-hmac")
            add("  ipsec ike keepalive use \(raT) off")
            add("  ipsec ike nat-traversal \(raT) on")
            add("  ipsec ike pre-shared-key \(raT) text \(m.remotePSK.isEmpty ? "事前共有鍵" : m.remotePSK)")
            add("  ipsec ike remote address \(raT) any")
            add(" l2tp tunnel disconnect time off")
            add(" l2tp keepalive use on 10 3")
            add(" l2tp keepalive log on")
            add(" ip tunnel tcp mss limit auto")
            add(" tunnel enable \(raT)")
            add("pp select anonymous")
            add(" pp bind tunnel\(raT)")
            add(" pp auth request mschap-v2")
            let users = m.remoteUsers.filter { !$0.name.isEmpty }
            if users.isEmpty {
                add(" pp auth username ユーザー名 パスワード")
            } else {
                for u in users {
                    add(" pp auth username \(u.name) \(u.password.isEmpty ? "パスワード" : u.password)")
                }
            }
            add(" ppp ipcp ipaddress on")
            add(" ppp ipcp msext on")
            add(" ppp ccp type none")
            add(" ip pp remote address pool \(m.remotePoolStart)-\(m.remotePoolEnd)")
            add(" ip pp mtu 1258")
            add(" pp enable anonymous")
            add("ip lan1 proxyarp on")
            add()
        }

        // ---- DHCPサーバー ----
        if m.dhcpEnabled {
            add("# --- DHCP サーバー ---")
            add("dhcp service server")
            add("dhcp server rfc2131 compliant except remain-silent")
            let lease = String(format: "%d:00", Int(m.dhcpLeaseHours))
            add("dhcp scope 1 \(m.dhcpStart)-\(m.dhcpEnd)/\(prefix) expire \(lease) maxexpire \(lease)")
            add()
        }

        // ---- DNS ----
        if m.secDns {
        add("# --- DNS ---")
        add("dns host lan1")
        if m.dnsRecursive { add("dns service recursive") }
        if m.dnsFromProvider {
            switch m.wanType {
            case .pppoe:
                add("dns server pp 1")
                add("dns server select 500000 pp 1 any . restrict pp 1")
            case .dhcp:
                add("dns server dhcp lan2")
            case .ipoe:
                add("dns server dhcp lan2")   // NGNから取得したIPv6 DNSを利用
            case .staticIP:
                if !m.dnsServers.isEmpty { add("dns server \(m.dnsServers)") }
            }
        } else if !m.dnsServers.isEmpty {
            add("dns server \(m.dnsServers)")
        }
        add()
        }  // end secDns

        // ---- 管理アクセス ----
        if m.secMgmt {
        add("# --- 管理アクセス ---")
        if m.enableSSH {
            add("sshd service on")
            add("sshd host key generate  # ※初回のみ手動実行が必要な場合あり")
        } else {
            add("sshd service off")
        }
        add("telnetd service \(m.enableTelnet ? "on" : "off")")
        if m.enableHTTP {
            add("httpd service on")
        } else {
            add("httpd service off")
        }
        if m.blockWanAdmin {
            if m.useSecurityFilter {
                add("# WAN側からの管理アクセスは上記セキュリティフィルタ(暗黙のdeny)で遮断されます")
            } else {
                add("# WAN側からの管理アクセスを遮断 (セキュリティフィルタOFF時の補助設定)")
                add("ip filter 100000 pass \(lanNet) * * * *")
                add("ip filter 100099 reject * * * * *")
                switch m.wanType {
                case .pppoe:    add("ip pp secure filter in 100099")
                case .dhcp:     add("ip lan2 secure filter in 100099")
                case .staticIP: add("ip lan2 secure filter in 100099")
                case .ipoe:     add("ip tunnel secure filter in 100099")
                }
            }
        }
        add()
        }  // end secMgmt

        // ---- NTP ----
        if m.ntpEnabled {
            add("# --- 時刻同期 (NTP) ---")
            add("schedule at 1 startup * ntpdate \(m.ntpServer) syslog")
            add("schedule at 2 */6:00 * ntpdate \(m.ntpServer) syslog")
            add()
        }

        // ---- Syslog ----
        if m.secSyslog {
            add("# --- Syslog ---")
            if !m.syslogHost.isEmpty { add("syslog host \(m.syslogHost)") }
            add("syslog notice \(m.syslogNotice ? "on" : "off")")
            add("syslog info \(m.syslogInfo ? "on" : "off")")
            add("syslog debug \(m.syslogDebug ? "on" : "off")")
            add()
        }

        // ---- パスワード (手動設定の案内) ----
        if m.secBasic {
            add("# --- 管理パスワード (コンソールで対話的に設定してください) ---")
            if !m.adminPassword.isEmpty {
                add("#   administrator password   → \(m.adminPassword)")
            } else {
                add("#   administrator password   (管理パスワード)")
            }
            // ログインユーザー未指定時のみ、無名ログインのパスワード設定を案内
            if m.loginUser.isEmpty {
                if !m.loginPassword.isEmpty {
                    add("#   login password           → \(m.loginPassword)")
                } else {
                    add("#   login password           (ログインパスワード)")
                }
            }
            add()
        }

        add("# --- 設定を保存 ---")
        add("save")

        return L.joined(separator: "\n")
    }

    // 標準セキュリティフィルタ (in) ： 基本 + 開放ポート
    private static func inFilterList(_ m: ConfigModel) -> String {
        var nums = ["200003", "200020", "200021", "200022", "200023", "200024", "200025"]
        if m.passICMP { nums.append("200030") }
        nums.append("200032")
        if m.secPortForward {
            for (i, pf) in m.portForwards.enumerated() where !pf.innerIP.isEmpty && !pf.port.isEmpty {
                nums.append(String(200040 + i))
            }
        }
        // VPN (IKE/ESP/NAT-T) の受信許可 (拠点間 or リモートアクセス)
        let activeVpn = m.vpnEnabled ? m.vpnTunnels.filter { !$0.psk.isEmpty && !$0.remoteLan.isEmpty } : []
        if !activeVpn.isEmpty || m.remoteEnabled {
            nums.append(contentsOf: ["200100", "200101", "200102"])
        }
        return nums.joined(separator: " ")
    }

    // 標準セキュリティフィルタ (out) ： ステートフル
    private static func outFilterList() -> String {
        return "200013 200020 200021 200022 200023 200024 200025 200099 dynamic 200080 200081 200082 200083 200084 200085 200098 200099"
    }

    // IPoE用 IPv6フィルタ (in / out)
    private static func ipv6InList() -> String {
        return "101000 101001 101002 101003 101020 101021 101022 101023 101024 101025 dynamic 101080 101081 101082 101083 101084 101085 101098 101099"
    }
    private static func ipv6OutList() -> String {
        return "101099 dynamic 101080 101081 101082 101083 101084 101085 101098 101099"
    }
}
