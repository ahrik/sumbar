import SwiftUI

struct SecurityContextView: View {
    @Bindable var store: MarketStore
    let instrument: Instrument
    let detail: SecurityDetail
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Surface {
                VStack(alignment: .leading, spacing: 11) {
                    Label(store.l10n("Подробности бумаги"), systemImage: "doc.text.magnifyingglass").font(.system(size: 13, weight: .semibold))
                    if let issuer = detail.issuerName { Text(issuer).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
                    if let sector = detail.sector { row(store.l10n("Сектор"), sector) }
                    if let session = detail.session {
                        Text(session.date.map { store.l10n("Показатели за сессию \($0)") } ?? store.l10n("Дата сессии не указана"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        row(store.l10n("Открытие"), Money.format(session.open, digits: 6))
                        row(store.l10n("Максимум"), Money.format(session.high, digits: 6))
                        row(store.l10n("Минимум"), Money.format(session.low, digits: 6))
                        row(session.volumeUnit == "shares" || session.volumeUnit == "bonds" ? store.l10n("Объём, шт.") : store.l10n("Объём, единицы источника"), Money.format(session.volume))
                        row(store.l10n("Оборот"), Money.format(session.turnover) + " " + instrument.currency)
                    }
                    if instrument.kind == "bond" {
                        Divider()
                        row(store.l10n("Номинал"), Money.format(detail.faceValue) + " " + instrument.currency)
                        row(store.l10n("Ставка купона"), Money.format(detail.coupon, digits: 4) + "%")
                        row(store.l10n("Выплат купона в год"), detail.couponFrequency.map(String.init) ?? "—")
                        row(store.l10n("Дата выпуска"), detail.issueDate ?? "—")
                        row(store.l10n("Погашение"), detail.maturityDate ?? "—")
                        Text(store.l10n("Периодичность не определяет дату следующей выплаты. Доходность к погашению здесь не рассчитывается."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(store.l10n("Пустые поля не опубликованы источником. Данные UZSE через Finmind."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let disclosures = detail.disclosures, !disclosures.isEmpty {
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(store.l10n("Раскрытия эмитента"), systemImage: "doc.text").font(.system(size: 13, weight: .semibold))
                        ForEach(Array(disclosures.prefix(5))) { disclosure in
                            VStack(alignment: .leading, spacing: 4) {
                                Link(disclosure.title, destination: disclosure.url).font(.system(size: 12)).lineLimit(3)
                                Text((disclosure.date ?? "—") + " · " + (disclosure.url.host ?? ""))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        Text(store.l10n("Ссылки открывают первоисточник. Названия документов сохранены на языке публикации."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }.font(.system(size: 11))
    }
}
