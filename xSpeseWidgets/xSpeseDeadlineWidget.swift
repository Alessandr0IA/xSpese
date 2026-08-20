import SwiftUI
import WidgetKit

@main
struct xSpeseWidgets: WidgetBundle {
    var body: some Widget {
        DeadlineWidget()
        MonthlyExpenseWidget()
        SyncStatusWidget()
        ExpenseOverviewWidget()
    }
}

// MARK: - Prossima scadenza

struct DeadlineWidget: Widget {
    let kind = "xSpeseDeadlines"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DeadlineTimelineProvider()) { entry in
            DeadlineWidgetView(entry: entry)
                .xSpeseWidgetBackground(colors: [.blue.opacity(0.16), .teal.opacity(0.08)])
                .widgetURL(URL(string: "xspese://scadenze"))
        }
        .configurationDisplayName("Prossima scadenza")
        .description("Mostra la prossima scadenza registrata in xSpese.")
        .supportedFamilies([.systemSmall])
    }
}

struct DeadlineTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: DeadlineWidgetSnapshot?
}

struct DeadlineTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeadlineTimelineEntry {
        DeadlineTimelineEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeadlineTimelineEntry) -> Void) {
        completion(.init(date: .now, snapshot: context.isPreview ? .preview : DeadlineWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlineTimelineEntry>) -> Void) {
        completion(.init(entries: [.init(date: .now, snapshot: DeadlineWidgetStore.load())], policy: .after(.nextWidgetRefresh)))
    }
}

struct DeadlineWidgetView: View {
    let entry: DeadlineTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.blue)
                Text("Scadenze")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if remainingCount > 0 {
                    Text("+\(remainingCount)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.14), in: Capsule())
                }
            }

            if let deadline = nextDeadline {
                Spacer(minLength: 0)
                Text(deadline.title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                VStack(alignment: .leading, spacing: 3) {
                    Label(dueLabel(for: deadline, relativeTo: entry.date), systemImage: deadline.dueDate < entry.date.startOfDay ? "exclamationmark.circle.fill" : "calendar")
                        .font(.caption)
                        .foregroundStyle(deadline.dueDate < entry.date.startOfDay ? .red : .secondary)

                    if let amount = WidgetFormatting.money(deadline.amount, currency: deadline.currency) {
                        Text(amount)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            } else if entry.snapshot != nil {
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Tutto in ordine")
                    .font(.headline)
                Text("Nessuna scadenza aperta")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                WidgetEmptyState(icon: "arrow.triangle.2.circlepath", title: "Apri xSpese", subtitle: "Aggiorna le scadenze", color: .blue)
            }
        }
    }

    private var nextDeadline: DeadlineWidgetItem? { entry.snapshot?.deadlines.first }
    private var remainingCount: Int { max((entry.snapshot?.deadlines.count ?? 1) - 1, 0) }
}

// MARK: - Spese del mese

struct MonthlyExpenseWidget: Widget {
    let kind = "xSpeseMonthly"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MonthlyTimelineProvider()) { entry in
            MonthlyExpenseWidgetView(entry: entry)
                .xSpeseWidgetBackground(colors: [.indigo.opacity(0.17), .purple.opacity(0.08)])
                .widgetURL(URL(string: "xspese://dashboard"))
        }
        .configurationDisplayName("Spese del mese")
        .description("Il totale del mese e la categoria con la spesa maggiore.")
        .supportedFamilies([.systemSmall])
    }
}

struct MonthlyTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: MonthlyWidgetSnapshot?
}

struct MonthlyTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthlyTimelineEntry {
        .init(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (MonthlyTimelineEntry) -> Void) {
        completion(.init(date: .now, snapshot: context.isPreview ? .preview : MonthlyWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthlyTimelineEntry>) -> Void) {
        completion(.init(entries: [.init(date: .now, snapshot: MonthlyWidgetStore.load())], policy: .after(.nextWidgetRefresh)))
    }
}

struct MonthlyExpenseWidgetView: View {
    let entry: MonthlyTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Spese del mese", systemImage: "chart.bar.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)

            if let snapshot = entry.snapshot {
                Text(WidgetFormatting.month(year: snapshot.year, month: snapshot.month))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(WidgetFormatting.money(snapshot.total, currency: snapshot.currency) ?? "—")
                    .font(.title2.bold())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if let category = snapshot.topCategory {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Più speso")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(category)
                                .lineLimit(1)
                            if let amount = WidgetFormatting.money(snapshot.topCategoryTotal, currency: snapshot.currency) {
                                Spacer(minLength: 2)
                                Text(amount)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption.weight(.medium))
                    }
                }
            } else {
                WidgetEmptyState(icon: "chart.bar.xaxis", title: "Nessun report", subtitle: "Apri la Dashboard", color: .indigo)
            }
        }
    }
}

// MARK: - Stato sincronizzazione

struct SyncStatusWidget: Widget {
    let kind = "xSpeseSync"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SyncTimelineProvider()) { entry in
            SyncStatusWidgetView(entry: entry)
                .xSpeseWidgetBackground(colors: [.teal.opacity(0.17), .cyan.opacity(0.07)])
                .widgetURL(URL(string: "xspese://movimenti"))
        }
        .configurationDisplayName("Sincronizzazione")
        .description("Controlla le spese in attesa e gli eventuali errori di invio.")
        .supportedFamilies([.systemSmall])
    }
}

struct SyncTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: SyncWidgetSnapshot?
}

struct SyncTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SyncTimelineEntry {
        .init(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SyncTimelineEntry) -> Void) {
        completion(.init(date: .now, snapshot: context.isPreview ? .preview : SyncWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SyncTimelineEntry>) -> Void) {
        completion(.init(entries: [.init(date: .now, snapshot: SyncWidgetStore.load())], policy: .after(.nextWidgetRefresh)))
    }
}

struct SyncStatusWidgetView: View {
    let entry: SyncTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sincronizzazione", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)

            if let snapshot = entry.snapshot {
                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(snapshot.pendingCount)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text(snapshot.pendingCount == 1 ? "da inviare" : "da inviare")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if snapshot.failedCount > 0 {
                    Label("\(snapshot.failedCount) non riuscite", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else if snapshot.pendingCount == 0 {
                    Label("Tutto sincronizzato", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Label("In attesa del server", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastSync = snapshot.lastSuccessfulSync {
                    HStack(spacing: 3) {
                        Text("Ultimo invio")
                        Text(lastSync, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else {
                WidgetEmptyState(icon: "wifi.exclamationmark", title: "Stato non noto", subtitle: "Apri xSpese", color: .teal)
            }
        }
    }
}

// MARK: - Panoramica

struct ExpenseOverviewWidget: Widget {
    let kind = "xSpeseOverview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OverviewTimelineProvider()) { entry in
            ExpenseOverviewWidgetView(entry: entry)
                .xSpeseWidgetBackground(colors: [.blue.opacity(0.13), .purple.opacity(0.08)])
                .widgetURL(URL(string: "xspese://dashboard"))
        }
        .configurationDisplayName("Panoramica xSpese")
        .description("Totale del mese, prossima scadenza e stato della sincronizzazione.")
        .supportedFamilies([.systemMedium])
    }
}

struct OverviewTimelineEntry: TimelineEntry {
    let date: Date
    let monthly: MonthlyWidgetSnapshot?
    let deadlines: DeadlineWidgetSnapshot?
    let sync: SyncWidgetSnapshot?
}

struct OverviewTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> OverviewTimelineEntry {
        .init(date: .now, monthly: .preview, deadlines: .preview, sync: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (OverviewTimelineEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OverviewTimelineEntry>) -> Void) {
        completion(.init(entries: [currentEntry()], policy: .after(.nextWidgetRefresh)))
    }

    private func currentEntry() -> OverviewTimelineEntry {
        .init(date: .now, monthly: MonthlyWidgetStore.load(), deadlines: DeadlineWidgetStore.load(), sync: SyncWidgetStore.load())
    }
}

struct ExpenseOverviewWidgetView: View {
    let entry: OverviewTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("xSpese", systemImage: "wallet.bifold.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Spacer()
                if let sync = entry.sync {
                    Label("\(sync.pendingCount)", systemImage: sync.failedCount > 0 ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sync.failedCount > 0 ? .red : .secondary)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("QUESTO MESE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let monthly = entry.monthly {
                        Text(WidgetFormatting.money(monthly.total, currency: monthly.currency) ?? "—")
                            .font(.title2.bold())
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        if let category = monthly.topCategory {
                            Label(category, systemImage: "chart.bar.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Apri la Dashboard")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 5) {
                    Text("PROSSIMA SCADENZA")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let deadline = entry.deadlines?.deadlines.first {
                        Text(deadline.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Label(dueLabel(for: deadline, relativeTo: entry.date), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(deadline.dueDate < entry.date.startOfDay ? .red : .secondary)
                    } else if entry.deadlines != nil {
                        Label("Nessuna scadenza", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text("Apri Scadenze")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Componenti condivisi

private struct WidgetEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        Spacer(minLength: 0)
        Image(systemName: icon)
            .font(.title2)
            .foregroundStyle(color)
        Text(title)
            .font(.headline)
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private extension View {
    func xSpeseWidgetBackground(colors: [Color]) -> some View {
        containerBackground(for: .widget) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private enum WidgetFormatting {
    static func money(_ rawValue: String?, currency: String) -> String? {
        guard let rawValue,
              let amount = Decimal(string: rawValue, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return amount.formatted(.currency(code: currency).precision(.fractionLength(0...2)))
    }

    static func month(year: Int, month: Int) -> String {
        guard let date = Calendar.current.date(from: DateComponents(year: year, month: month)) else { return "Mese corrente" }
        return date.formatted(.dateTime.month(.wide).year()).capitalized
    }
}

private extension Date {
    static var nextWidgetRefresh: Date {
        Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
    }

    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}

private func dueLabel(for deadline: DeadlineWidgetItem, relativeTo referenceDate: Date) -> String {
    let calendar = Calendar.current
    let difference = calendar.dateComponents([.day], from: referenceDate.startOfDay, to: deadline.dueDate.startOfDay).day ?? 0
    switch difference {
    case ..<0: return difference == -1 ? "Scaduta ieri" : "Scaduta da \(-difference) giorni"
    case 0: return "Scade oggi"
    case 1: return "Scade domani"
    default: return deadline.dueDate.formatted(.dateTime.day().month(.abbreviated))
    }
}

private extension DeadlineWidgetSnapshot {
    static var preview: DeadlineWidgetSnapshot {
        .init(
            updatedAt: .now,
            deadlines: [
                .init(
                    id: 1,
                    title: "Bolletta elettrica",
                    dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now,
                    amount: "87.40",
                    currency: "EUR",
                    priority: "alta"
                )
            ]
        )
    }
}

private extension MonthlyWidgetSnapshot {
    static var preview: MonthlyWidgetSnapshot {
        let components = Calendar.current.dateComponents([.year, .month], from: .now)
        return .init(
            updatedAt: .now,
            year: components.year ?? 2026,
            month: components.month ?? 1,
            total: "1247.80",
            currency: "EUR",
            topCategory: "Supermercato",
            topCategoryTotal: "356.20"
        )
    }
}

private extension SyncWidgetSnapshot {
    static var preview: SyncWidgetSnapshot {
        .init(updatedAt: .now, pendingCount: 2, failedCount: 0, lastSuccessfulSync: .now.addingTimeInterval(-420))
    }
}

#Preview("Scadenza", as: .systemSmall) {
    DeadlineWidget()
} timeline: {
    DeadlineTimelineEntry(date: .now, snapshot: .preview)
}

#Preview("Spese del mese", as: .systemSmall) {
    MonthlyExpenseWidget()
} timeline: {
    MonthlyTimelineEntry(date: .now, snapshot: .preview)
}

#Preview("Sincronizzazione", as: .systemSmall) {
    SyncStatusWidget()
} timeline: {
    SyncTimelineEntry(date: .now, snapshot: .preview)
}

#Preview("Panoramica", as: .systemMedium) {
    ExpenseOverviewWidget()
} timeline: {
    OverviewTimelineEntry(date: .now, monthly: .preview, deadlines: .preview, sync: .preview)
}
