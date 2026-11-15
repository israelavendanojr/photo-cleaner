/// A number Developer mode can tune in Admin Tools: `FreeTierTunable`, `CompressionTunable`. `TunableRow`
/// shows any of them.
protocol AdminTunable: RawRepresentable<String> {
    var title: String { get }
    /// Shown after the value, e.g. "min".
    var unit: String { get }
    var range: ClosedRange<Int> { get }
    /// The stepper's step.
    var step: Int { get }
}
