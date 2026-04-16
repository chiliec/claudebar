import SwiftUI

struct UsageDetailView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            if let usage = state.usage {
                fiveHourSection(usage)
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                sevenDaySection(usage)
                if let extra = usage.extraUsage, extra.isEnabled,
                   let used = extra.usedCredits, let limit = extra.monthlyLimit, limit > 0 {
                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    extraUsageSection(used: used, limit: limit)
                }
            } else if state.isLoading {
                ProgressView()
                    .padding(40)
            } else if let error = state.error {
                Text(error.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                Text("usage.noData", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(40)
            }
            if let update = state.availableUpdate {
                updateBanner(version: update.version, url: update.url)
            }
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("usage.title", bundle: .module)
                .font(.headline)
            Spacer()
            if let usage = state.usage {
                if #available(macOS 26.0, *) {
                    Text(tierLabel(usage))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .glassEffect()
                } else {
                    Text(tierLabel(usage))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func fiveHourSection(_ usage: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let utilization = usage.fiveHour?.utilization ?? 0
            let color = UsageColor.forUtilization(utilization).swiftUIColor

            HStack {
                Text("usage.fiveHourWindow", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let reset = usage.fiveHour?.resetsAt {
                    Text("usage.resetsIn \(resetTimeString(reset))", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                    if utilization > 0 {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(width: max(geo.size.width * utilization, 8))
                            .animation(.easeInOut(duration: 0.4), value: utilization)
                    }
                    Text(verbatim: "\(Int(utilization * 100))%")
                        .font(.subheadline.bold())
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func sevenDaySection(_ usage: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("usage.sevenDayWindows", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            slimBar(label: String(localized: "usage.total", bundle: .module), utilization: usage.sevenDay.utilization, resetDate: usage.sevenDay.resetsAt, color: .blue)

            if let opus = usage.sevenDayOpus {
                slimBar(label: String(localized: "usage.opus", bundle: .module), utilization: opus.utilization, resetDate: opus.resetsAt, color: Color(red: 0.75, green: 0.52, blue: 0.99))
            }

            if let sonnet = usage.sevenDaySonnet {
                slimBar(label: String(localized: "usage.sonnet", bundle: .module), utilization: sonnet.utilization, resetDate: sonnet.resetsAt, color: Color(red: 0.38, green: 0.65, blue: 0.98))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func slimBar(label: String, utilization: Double, resetDate: Date?, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "\(Int(utilization * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let date = resetDate {
                    (Text(verbatim: "· ") + Text("usage.resetsIn \(resetTimeString(date))", bundle: .module))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                    if utilization > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: max(geo.size.width * utilization, 6))
                            .animation(.easeInOut(duration: 0.4), value: utilization)
                    }
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private func updateBanner(version: String, url: String) -> some View {
        if let destination = URL(string: url) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.subheadline)
                Text("update.versionAvailable \(version)", bundle: .module)
                    .font(.subheadline)
                Spacer()
                Link(destination: destination) {
                    Text("update.download", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .modifier(GlassBannerModifier())
        }
    }

    private func extraUsageSection(used: Double, limit: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("usage.extraCredits", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            slimBar(
                label: String(localized: "usage.creditsUsed \(String(format: "%.2f", used / 100)) \(String(format: "%.0f", limit / 100))", bundle: .module),
                utilization: min(used / limit, 1.0),
                resetDate: nil,
                color: .teal
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let lastUpdated = state.lastUpdated {
                Text("usage.updatedAgo \(lastUpdated, style: .relative)", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if state.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Button {
                    Task { await state.refreshUsage() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                }
                .modifier(FooterButtonModifier())
                .help(String(localized: "action.refresh", bundle: .module))
            }
            Button {
                state.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
            }
            .modifier(FooterButtonModifier())
            .help(String(localized: "settings.title", bundle: .module))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func tierLabel(_ usage: UsageResponse) -> String {
        if usage.sevenDayOpus != nil {
            if let extra = usage.extraUsage, let limit = extra.monthlyLimit {
                return String(localized: "tier.maxWithLimit \(Int(limit / 100))", bundle: .module)
            }
            return String(localized: "tier.max", bundle: .module)
        }
        return String(localized: "tier.pro", bundle: .module)
    }

    private func resetTimeString(_ date: Date) -> String {
        let interval = max(0, date.timeIntervalSinceNow)
        let totalSeconds = Int(interval)
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 { return String(localized: "time.daysHours \(days) \(hours)", bundle: .module) }
        return String(localized: "time.hoursMinutes \(hours) \(minutes)", bundle: .module)
    }
}

// MARK: - Liquid Glass Modifiers

private struct FooterButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .foregroundStyle(.blue)
                .buttonStyle(.glass)
        } else {
            content
                .foregroundStyle(.blue)
                .buttonStyle(.plain)
        }
    }
}

private struct GlassBannerModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.blue), in: .rect(cornerRadius: 8))
        } else {
            content
                .background(.blue.opacity(0.08))
        }
    }
}
