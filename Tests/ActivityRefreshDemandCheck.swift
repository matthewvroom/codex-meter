@main
enum ActivityRefreshDemandCheck {
    static func main() {
        precondition(!ActivityRefreshDemand(popoverVisible: false, sectionExpanded: false, activityDisplaySelected: false).requiresRefresh)
        precondition(!ActivityRefreshDemand(popoverVisible: false, sectionExpanded: true, activityDisplaySelected: false).requiresRefresh)
        precondition(!ActivityRefreshDemand(popoverVisible: true, sectionExpanded: false, activityDisplaySelected: false).requiresRefresh)

        let visible = ActivityRefreshDemand(popoverVisible: true, sectionExpanded: true, activityDisplaySelected: false)
        precondition(visible.requiresRefresh)
        precondition(!visible.requiresPolling)

        let menuBar = ActivityRefreshDemand(popoverVisible: false, sectionExpanded: false, activityDisplaySelected: true)
        precondition(menuBar.requiresRefresh)
        precondition(menuBar.requiresPolling)

        print("Activity refresh demand checks passed")
    }
}
