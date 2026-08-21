public struct ActivityRefreshDemand: Equatable, Sendable {
    public let popoverVisible: Bool
    public let sectionExpanded: Bool
    public let activityDisplaySelected: Bool

    public init(popoverVisible: Bool, sectionExpanded: Bool, activityDisplaySelected: Bool) {
        self.popoverVisible = popoverVisible
        self.sectionExpanded = sectionExpanded
        self.activityDisplaySelected = activityDisplaySelected
    }

    public var requiresRefresh: Bool {
        activityDisplaySelected || (popoverVisible && sectionExpanded)
    }

    public var requiresPolling: Bool { activityDisplaySelected }
}
