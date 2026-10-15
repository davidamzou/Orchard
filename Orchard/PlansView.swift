//
//  PlansView.swift
//  Orchard
//

import SwiftData
import SwiftUI
import UserNotifications

/// Autopilot: monthly investing reminders, plus a projection of where steady saving leads.
struct PlansView: View {
    @Environment(\.modelContext) private var context
    @Environment(MarketData.self) private var marketData
    @Query(sort: \AutopilotPlan.createdAt) private var plans: [AutopilotPlan]
    @State private var isAddingPlan = false
    @State private var notificationsDenied = false

    // Projection inputs
    @AppStorage("projection.monthly") private var monthly = 150.0
    @AppStorage("projection.rate") private var rate = 7.0
    @AppStorage("projection.years") private var years = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Autopilot", subtitle: "Practice investing every month. Autopilot buys your chosen amount with practice cash, at the live price.")
                    .padding(.top, 8)
                planList
                projection
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .foregroundStyle(Palette.ink)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.paper)
        .buttonStyle(.plain)
        .sheet(isPresented: $isAddingPlan) {
            PlanSheet { ticker, amount, day in
                let plan = AutopilotPlan(ticker: ticker, amount: amount, dayOfMonth: day)
                context.insert(plan)
                _ = context.stock(ticker: ticker)
                try? context.save()
                Task {
                    await schedule(plan)
                    await marketData.refreshAll(in: context)
                }
            }
        }
        .task { await checkNotificationStatus() }
    }

    private var planList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("MONTHLY PLANS")
            if !marketData.autopilotLog.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(marketData.autopilotLog, id: \.self) { line in
                        Text(line).font(.inter(11))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.lime)
            }
            if notificationsDenied {
                Text("Notifications are off for Orchard, so reminders won't appear. Turn them on in Settings.")
                    .font(.inter(11))
                    .foregroundStyle(Palette.loss)
            }
            VStack(spacing: 0) {
                ForEach(plans) { plan in
                    PlanRow(plan: plan) {
                        Task { await plan.isEnabled ? schedule(plan) : unschedule(plan) }
                    } onDelete: {
                        unscheduleNow(plan)
                        context.delete(plan)
                        try? context.save()
                    }
                }
            }
            PrimaryButton(title: plans.isEmpty ? "Start my first plan" : "Add a plan") { isAddingPlan = true }
        }
    }

    private var projection: some View {
        let total = Projection.futureValue(monthly: monthly, annualRate: rate, years: years)
        let contributed = monthly * Double(years * 12)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("WHERE IT LEADS")
                .foregroundStyle(Palette.lime)
            Text(total.money(decimals: 0))
                .font(.serif(64))
                .foregroundStyle(Palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 12)
            Text("after \(years) years · \(contributed.money(decimals: 0)) put in, \((total - contributed).money(decimals: 0)) of growth")
                .font(.inter(11))
                .foregroundStyle(Palette.lime)
                .padding(.bottom, 20)

            slider("MONTHLY", monthly.money(decimals: 0), value: $monthly, in: 5...2_000, step: 5)
            slider("YEARLY RETURN", "\(rate.decimal(1))%", value: $rate, in: 0...12, step: 0.5)
            slider("YEARS", "\(years)", value: Binding(get: { Double(years) }, set: { years = Int($0) }), in: 1...40, step: 1)

            Text("An estimate, not a promise. Markets go down as well as up.")
                .font(.inter(9.5, relativeTo: .caption2))
                .foregroundStyle(Palette.muted)
                .padding(.top, 8)
        }
        .padding(18)
        .background(Palette.deepInk)
    }

    private func slider(_ title: String, _ value: String, value binding: Binding<Double>,
                        in range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.inter(8.5, weight: .medium, relativeTo: .caption2))
                Spacer()
                Text(value).font(.inter(12, weight: .semibold))
            }
            .foregroundStyle(Palette.paper)
            Slider(value: binding, in: range, step: step)
                .tint(Palette.lime)
                .accessibilityLabel(title.capitalized)
                .accessibilityValue(value)
        }
        .padding(.bottom, 12)
    }

    // MARK: Notifications

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied && !plans.isEmpty
    }

    private func schedule(_ plan: AutopilotPlan) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationsDenied = !granted
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Autopilot day"
        content.body = "Your practice plan buys \(plan.amount.money(decimals: 0)) of \(plan.ticker) today. Open Orchard to see how your orchard grows."
        content.sound = .default
        var date = DateComponents()
        date.day = plan.dayOfMonth
        date.hour = 9
        let request = UNNotificationRequest(identifier: plan.notificationID, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true))
        try? await center.add(request)
    }

    private func unschedule(_ plan: AutopilotPlan) async { unscheduleNow(plan) }

    private func unscheduleNow(_ plan: AutopilotPlan) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [plan.notificationID])
    }
}

private struct PlanRow: View {
    @Bindable var plan: AutopilotPlan
    var onToggle: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 11) {
                TickerMark(ticker: plan.ticker, isAccent: plan.isEnabled)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(plan.amount.money(decimals: 0)) every month")
                        .font(.inter(13, weight: .medium))
                    Text(plan.lastRun.map { "day \(plan.dayOfMonth) · last bought \($0.formatted(date: .abbreviated, time: .omitted))" }
                         ?? "on day \(plan.dayOfMonth) of each month")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Toggle("Reminder", isOn: $plan.isEnabled)
                    .labelsHidden()
                    .tint(Palette.ink)
                    .onChange(of: plan.isEnabled) { onToggle() }
            }
            Rectangle().fill(Palette.divider).frame(height: 1)
        }
        .padding(.bottom, 10)
        .contentShape(.rect)
        .contextMenu {
            Button("Delete plan", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

private struct PlanSheet: View {
    var onSave: (String, Double, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(MarketData.self) private var marketData
    @State private var ticker = ""
    @State private var amount: Double? = 50
    @State private var day = 1
    @State private var results: [FinnhubClient.SearchResult] = []

    private var isValid: Bool { !ticker.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ticker, e.g. VOO", text: $ticker)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                    ForEach(results) { result in
                        Button {
                            ticker = result.symbol
                            results = []
                        } label: {
                            HStack {
                                Text(result.symbol).fontWeight(.semibold)
                                Text(result.description).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                } header: {
                    Text("Invest in")
                }
                Section {
                    LabeledContent("Amount") {
                        TextField("$0", value: $amount, format: .currency(code: "USD"))
                            .multilineTextAlignment(.trailing)
                            .decimalKeyboard()
                    }
                    Picker("Day of the month", selection: $day) {
                        ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
                    }
                } footer: {
                    Text("On that day, Orchard buys this amount with your practice cash at the live price (the next time you open the app) and sends a reminder at 9:00. No real money is used.")
                }
            }
            .navigationTitle("New plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        onSave(ticker.trimmingCharacters(in: .whitespaces).uppercased(), amount ?? 0, day)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .disabled(!isValid)
                }
            }
            .task(id: ticker) {
                let term = ticker.trimmingCharacters(in: .whitespaces)
                guard term.count >= 1, !results.contains(where: { $0.symbol == term.uppercased() }) else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                results = Array(((try? await marketData.search(term)) ?? []).prefix(5))
            }
        }
    }
}
