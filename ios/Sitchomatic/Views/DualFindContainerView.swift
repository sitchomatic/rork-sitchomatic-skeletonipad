import SwiftUI

struct DualFindContainerView: View {
    @State private var vm = DualFindViewModel()
    @State private var showSettings: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isRunning {
                    DualFindRunningView(vm: vm)
                } else {
                    DualFindSetupView(
                        vm: vm,
                        onStart: { vm.startRun() },
                        onResume: { vm.resumeRun() },
                        onSettings: { showSettings = true }
                    )
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                DualFindSettingsView(vm: vm)
            }
        }
        .withMainMenuButton()
        .preferredColorScheme(.dark)
        .tint(.purple)
    }
}
