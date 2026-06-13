import Foundation

private let localizationBundle: Bundle = {
    let name = "PastePilot_PastePilot"
    let candidates = [
        Bundle.main.resourceURL,
        Bundle.main.bundleURL,
        Bundle.main.executableURL?.deletingLastPathComponent(),
    ]
    for base in candidates.compactMap({ $0 }) {
        if let b = Bundle(url: base.appendingPathComponent(name + ".bundle")) {
            return b
        }
    }
    return Bundle.main
}()

extension String {
    var localized: String {
        NSLocalizedString(self, bundle: localizationBundle, comment: "")
    }

    func localized(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, bundle: localizationBundle, comment: ""), arguments: args)
    }
}
