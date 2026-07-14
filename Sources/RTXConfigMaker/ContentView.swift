import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var m = ConfigModel()
    @State private var copied = false

    // 差分機能
    @State private var existingConfig = ""
    @State private var diffGenOnly: [String] = []
    @State private var diffExistOnly: [String] = []
    @State private var diffComputed = false
    @State private var ignoreTrivial = true

    var config: String { ConfigGenerator.generate(m) }

    var body: some View {
        // 4カラム等幅 (入力 / 生成 / 既存 / 差分)
        HStack(spacing: 8) {
            // ================= ① 入力 =================
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    basicSection
                    lanSection
                    wanSection
                    dhcpSection
                    dnsSection
                    natSection
                    portForwardSection
                    vpnSection
                    remoteSection
                    securitySection
                    mgmtSection
                    ntpSection
                    syslogSection
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ================= ②③④ 生成 / 既存 / 差分 =================
            generatedBox
            existingBox
            diffBox
        }
        .padding(8)
        .frame(minWidth: 1280, minHeight: 680)
        // 入力・既存コンフィグ・無視設定が変わったら差分結果を無効化 (陳腐化防止)
        .onChange(of: existingConfig) { _ in diffComputed = false }
        .onChange(of: ignoreTrivial) { _ in diffComputed = false }
        .onChange(of: config) { _ in diffComputed = false }
    }

    // MARK: - 生成コンフィグ
    private var generatedBox: some View {
        boxContainer {
            HStack {
                Text("生成コンフィグ").font(.headline)
                Spacer()
                Text("\(config.split(separator: "\n").count) 行")
                    .font(.caption).foregroundColor(.secondary)
                Button(action: copy) {
                    Label(copied ? "コピー済" : "コピー",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        } content: {
            ScrollView([.vertical, .horizontal]) {
                Text(config)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
        }
    }

    // MARK: - 既存コンフィグ (貼り付け)
    private var existingBox: some View {
        boxContainer {
            HStack {
                Text("既存コンフィグ (貼り付け)").font(.headline)
                Spacer()
                Text("\(existingConfig.isEmpty ? 0 : existingConfig.split(separator: "\n").count) 行")
                    .font(.caption).foregroundColor(.secondary)
                Button {
                    existingConfig = ""
                    diffComputed = false
                } label: { Label("クリア", systemImage: "trash") }
                    .disabled(existingConfig.isEmpty)
            }
        } content: {
            HScrollTextEditor(text: $existingConfig)
                .padding(6)
                .overlay(alignment: .topLeading) {
                    if existingConfig.isEmpty {
                        Text("ここに既存のコンフィグを貼り付け")
                            .foregroundColor(.secondary)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - 差分
    private var diffBox: some View {
        boxContainer {
            HStack {
                Text("差分").font(.headline)
                Spacer()
                Toggle("空行/#無視", isOn: $ignoreTrivial)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Button {
                    computeDiff()
                } label: { Label("差分を表示", systemImage: "arrow.left.arrow.right") }
                    .disabled(existingConfig.isEmpty)
            }
        } content: {
            diffContent
        }
    }

    @ViewBuilder
    private var diffContent: some View {
        if !diffComputed {
            Text("「差分を表示」を押してください")
                .foregroundColor(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if diffGenOnly.isEmpty && diffExistOnly.isEmpty {
            Label("差分なし (一致)", systemImage: "checkmark.circle")
                .foregroundColor(.green)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        diffGroup(title: "生成コンフィグだけにある", lines: diffGenOnly,
                                  color: .green, symbol: "+")
                        if !diffGenOnly.isEmpty && !diffExistOnly.isEmpty {
                            Divider().padding(.vertical, 6)
                        }
                        diffGroup(title: "既存コンフィグだけにある", lines: diffExistOnly,
                                  color: .orange, symbol: "−")
                    }
                    .padding(12)
                    .frame(minWidth: geo.size.width, alignment: .topLeading)
                }
            }
        }
    }

    @ViewBuilder
    private func diffGroup(title: String, lines: [String], color: Color, symbol: String) -> some View {
        if !lines.isEmpty {
            Text("\(title) (\(lines.count)行)")
                .font(.caption.bold())
                .foregroundColor(color)
                .padding(.bottom, 2)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text("\(symbol) \(line)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(color)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    // 共通の枠 (3ボックスで同一スタイル・同サイズ)
    private func boxContainer<H: View, C: View>(
        @ViewBuilder header: () -> H,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(spacing: 0) {
            header().padding(10)
            Divider()
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    // 行単位の差分 (前後空白は無視 / 内容が1文字でも違えば別行扱い)
    private func computeDiff() {
        let (genOnly, existOnly) = ConfigDiff.compare(
            generated: config,
            existing: existingConfig,
            ignoreTrivial: ignoreTrivial
        )
        diffGenOnly = genOnly
        diffExistOnly = existOnly
        diffComputed = true
    }

    // MARK: - 基本
    private var basicSection: some View {
        SectionCard(header: "基本設定", icon: "gearshape", isOn: $m.secBasic) {
            LabeledContent("メモ / 管理名") {
                TextField("RTX1220", text: $m.memoTitle).textFieldStyle(.roundedBorder)
            }
            Toggle("コンソール文字コードを UTF-8 にする", isOn: $m.consoleUTF8)
            HStack {
                Text("ログインタイムアウト")
                Slider(value: $m.loginTimeout, in: 60...1800, step: 60)
                Text("\(Int(m.loginTimeout)) 秒").frame(width: 64, alignment: .trailing).monospacedDigit()
            }
            LabeledContent("管理パスワード") {
                TextField("administrator password", text: $m.adminPassword).textFieldStyle(.roundedBorder)
            }
            LabeledContent("ログインユーザー名") {
                TextField("admin (SSH/telnet用・任意)", text: $m.loginUser).textFieldStyle(.roundedBorder)
            }
            LabeledContent("ログインパスワード") {
                TextField("login password", text: $m.loginPassword).textFieldStyle(.roundedBorder)
            }
            if !m.loginUser.isEmpty {
                Text("→ login user \(m.loginUser) … として出力されます (対話設定不要)")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - LAN
    private var lanSection: some View {
        SectionCard(header: "LAN設定 (内部)", icon: "network", isOn: $m.secLan) {
            LabeledContent("LAN1 IPアドレス") {
                TextField("192.168.100.1", text: $m.lan1Address).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("プレフィックス長")
                Slider(value: $m.lan1Prefix, in: 8...30, step: 1)
                Text("/\(Int(m.lan1Prefix))").frame(width: 44, alignment: .trailing).monospacedDigit()
            }
        }
    }

    // MARK: - WAN
    private var wanSection: some View {
        SectionCard(header: "インターネット接続 (WAN)", icon: "globe", isOn: $m.secWan) {
            Picker("接続方式", selection: $m.wanType) {
                ForEach(WanType.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.radioGroup)

            switch m.wanType {
            case .pppoe:
                LabeledContent("PPPoE ユーザー名") {
                    TextField("user@isp", text: $m.pppoeUser).textFieldStyle(.roundedBorder)
                }
                LabeledContent("PPPoE パスワード") {
                    TextField("password", text: $m.pppoePass).textFieldStyle(.roundedBorder)
                }
                Toggle("常時接続 (always-on)", isOn: $m.pppoeAlwaysOn)
                mtuSlider
            case .dhcp:
                Text("LAN2 でIPアドレスを自動取得します。").font(.caption).foregroundColor(.secondary)
            case .staticIP:
                LabeledContent("WAN IPアドレス") {
                    TextField("203.0.113.2", text: $m.staticWanIP).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("プレフィックス長")
                    Slider(value: $m.staticWanPrefix, in: 8...32, step: 1)
                    Text("/\(Int(m.staticWanPrefix))").frame(width: 44, alignment: .trailing).monospacedDigit()
                }
                LabeledContent("デフォルトGW") {
                    TextField("203.0.113.1", text: $m.staticWanGateway).textFieldStyle(.roundedBorder)
                }
            case .ipoe:
                Picker("IPoE方式", selection: $m.ipoeMethod) {
                    ForEach(IPoEMethod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch m.ipoeMethod {
                case .dsLite:
                    Picker("プロバイダ", selection: $m.dsLiteProvider) {
                        ForEach(DsLiteProvider.allCases) { Text($0.rawValue).tag($0) }
                    }
                    LabeledContent("AFTR上書き (任意)") {
                        TextField(m.dsLiteProvider.aftr, text: $m.aftrOverride).textFieldStyle(.roundedBorder)
                    }
                    Text("DS-LiteはRTX側でNATしません (固定IP/ポート開放は不可)")
                        .font(.caption2).foregroundColor(.secondary)
                case .mapE:
                    Picker("プロバイダ", selection: $m.mapEProvider) {
                        ForEach(MapEProvider.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text("MAP-Eは割当てポート範囲のみ利用可。type名はファームで要確認")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Toggle("LAN側にIPv6を配布する", isOn: $m.distributeIPv6)
            }
        }
    }

    private var mtuSlider: some View {
        HStack {
            Text("MTU / MRU")
            Slider(value: $m.mtu, in: 1280...1500, step: 2)
            Text("\(Int(m.mtu))").frame(width: 48, alignment: .trailing).monospacedDigit()
        }
    }

    // MARK: - DHCP
    private var dhcpSection: some View {
        SectionCard(header: "DHCPサーバー", icon: "list.number", isOn: $m.dhcpEnabled) {
            LabeledContent("配布開始アドレス") {
                TextField("192.168.100.2", text: $m.dhcpStart).textFieldStyle(.roundedBorder)
            }
            LabeledContent("配布終了アドレス") {
                TextField("192.168.100.191", text: $m.dhcpEnd).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("リース時間")
                Slider(value: $m.dhcpLeaseHours, in: 1...168, step: 1)
                Text("\(Int(m.dhcpLeaseHours)) 時間").frame(width: 64, alignment: .trailing).monospacedDigit()
            }
        }
    }

    // MARK: - DNS
    private var dnsSection: some View {
        SectionCard(header: "DNS設定", icon: "magnifyingglass", isOn: $m.secDns) {
            Toggle("プロバイダ (ISP) からDNSを自動取得", isOn: $m.dnsFromProvider)
            LabeledContent(m.dnsFromProvider ? "手動DNS (任意)" : "DNSサーバー") {
                TextField("8.8.8.8 8.8.4.4", text: $m.dnsServers).textFieldStyle(.roundedBorder)
            }
            Toggle("再帰的DNS問い合わせを有効化", isOn: $m.dnsRecursive)
        }
    }

    // MARK: - NAT
    private var natSection: some View {
        SectionCard(header: "NAT / IPマスカレード", icon: "arrow.left.arrow.right", isOn: $m.naptEnabled) {
            Text("内部から外部への通信をIPマスカレードで変換します。ポート開放・リモートアクセスにも必要です。")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - ポート開放
    private var portForwardSection: some View {
        SectionCard(header: "ポート開放 (静的NAT)", icon: "arrow.down.forward.and.arrow.up.backward", isOn: $m.secPortForward) {
            if !m.naptEnabled {
                Text("NATが無効のため利用できません。").font(.caption).foregroundColor(.secondary)
            }
            ForEach($m.portForwards) { $pf in
                VStack(spacing: 6) {
                    HStack {
                        Picker("", selection: $pf.proto) {
                            Text("tcp").tag("tcp"); Text("udp").tag("udp")
                        }.labelsHidden().frame(width: 70)
                        TextField("ポート", text: $pf.port).textFieldStyle(.roundedBorder).frame(width: 70)
                        TextField("宛先IP", text: $pf.innerIP).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            m.portForwards.removeAll { $0.id == pf.id }
                        } label: { Image(systemName: "trash") }
                    }
                    TextField("メモ (任意)", text: $pf.memo).textFieldStyle(.roundedBorder)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }
            Button {
                m.portForwards.append(PortForward(innerIP: dhcpStartOrLan()))
            } label: { Label("ポート開放を追加", systemImage: "plus") }
                .disabled(!m.naptEnabled)
        }
    }

    private func dhcpStartOrLan() -> String {
        m.dhcpStart.isEmpty ? m.lan1Address : m.dhcpStart
    }

    // MARK: - 拠点間VPN
    private var vpnSection: some View {
        SectionCard(header: "拠点間VPN (IPsec)", icon: "lock.shield", isOn: $m.vpnEnabled) {
            Picker("暗号強度", selection: $m.vpnStrength) {
                ForEach(VpnStrength.allCases) { Text($0.rawValue).tag($0) }
            }
            ForEach($m.vpnTunnels) { $t in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("拠点名メモ", text: $t.memo).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            m.vpnTunnels.removeAll { $0.id == t.id }
                        } label: { Image(systemName: "trash") }
                    }
                    Picker("方式", selection: $t.mode) {
                        ForEach(VpnMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    switch t.mode {
                    case .main:
                        field("相手グローバルIP", "203.0.113.10", $t.peerAddress)
                    case .center:
                        field("相手拠点の識別名", "branch1", $t.peerName)
                        Text("※このルーターは固定IP側。相手(動的IP)から接続を受けます。")
                            .font(.caption2).foregroundColor(.secondary)
                    case .branch:
                        field("センターのグローバルIP", "203.0.113.1", $t.peerAddress)
                        field("自拠点の識別名", "branch1", $t.localName)
                    }
                    field("事前共有鍵 (PSK)", "共有パスワード", $t.psk)
                    field("相手側LAN (CIDR)", "192.168.200.0/24", $t.remoteLan)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }
            Button {
                m.vpnTunnels.append(VpnTunnel(memo: "拠点\(m.vpnTunnels.count + 1)"))
            } label: { Label("VPN拠点を追加", systemImage: "plus") }
        }
    }

    // MARK: - リモートアクセスVPN
    private var remoteSection: some View {
        SectionCard(header: "リモートアクセスVPN (L2TP/IPsec)", icon: "personalhotspot", isOn: $m.remoteEnabled) {
            field("事前共有鍵 (PSK)", "共有パスワード", $m.remotePSK)
            Text("接続ユーザー")
                .font(.caption).foregroundColor(.secondary)
            ForEach($m.remoteUsers) { $u in
                HStack {
                    TextField("ユーザー名", text: $u.name).textFieldStyle(.roundedBorder)
                    TextField("パスワード", text: $u.password).textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        m.remoteUsers.removeAll { $0.id == u.id }
                    } label: { Image(systemName: "trash") }
                }
            }
            Button {
                m.remoteUsers.append(RemoteUser())
            } label: { Label("ユーザーを追加", systemImage: "plus") }
            field("払い出しIP 開始", "192.168.100.201", $m.remotePoolStart)
            field("払い出しIP 終了", "192.168.100.210", $m.remotePoolEnd)
            Text("スマホ/PCから社内へ接続。NAT有効が前提です。")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func field(_ label: String, _ placeholder: String, _ binding: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField(placeholder, text: binding).textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - セキュリティ
    private var securitySection: some View {
        SectionCard(header: "フィルタ / セキュリティ", icon: "shield", isOn: $m.useSecurityFilter) {
            Toggle("外部からのICMP(ping)を許可", isOn: $m.passICMP)
        }
    }

    // MARK: - 管理アクセス
    private var mgmtSection: some View {
        SectionCard(header: "管理アクセス", icon: "terminal", isOn: $m.secMgmt) {
            Toggle("SSH (sshd) を有効にする", isOn: $m.enableSSH)
            Toggle("TELNET を有効にする", isOn: $m.enableTelnet)
            Toggle("Web設定画面 (HTTP GUI) を有効にする", isOn: $m.enableHTTP)
            Toggle("WAN側からの管理アクセスを拒否", isOn: $m.blockWanAdmin)
        }
    }

    // MARK: - NTP
    private var ntpSection: some View {
        SectionCard(header: "時刻同期 (NTP)", icon: "clock", isOn: $m.ntpEnabled) {
            LabeledContent("NTPサーバー") {
                TextField("ntp.nict.jp", text: $m.ntpServer).textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Syslog
    private var syslogSection: some View {
        SectionCard(header: "Syslog", icon: "doc.text", isOn: $m.secSyslog) {
            LabeledContent("ログ送信先ホスト (任意)") {
                TextField("192.168.100.10", text: $m.syslogHost).textFieldStyle(.roundedBorder)
            }
            Toggle("notice レベルを記録", isOn: $m.syslogNotice)
            Toggle("info レベルを記録", isOn: $m.syslogInfo)
            Toggle("debug レベルを記録", isOn: $m.syslogDebug)
        }
    }
}

// MARK: - 見出し付きグループ (カテゴリのON/OFFチェック付き)
private struct SectionCard<Content: View>: View {
    let header: String
    let icon: String
    var isOn: Binding<Bool>? = nil
    @ViewBuilder let content: Content

    private var enabled: Bool { isOn?.wrappedValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let isOn {
                    Toggle("", isOn: isOn).toggleStyle(.checkbox).labelsHidden()
                }
                Image(systemName: icon).foregroundColor(enabled ? .accentColor : .secondary)
                Text(header).font(.headline).foregroundColor(enabled ? .primary : .secondary)
                Spacer(minLength: 0)
                if isOn != nil && !enabled {
                    Text("未出力").font(.caption2).foregroundColor(.secondary)
                }
            }
            if enabled {
                VStack(alignment: .leading, spacing: 8) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(enabled ? 1 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
