import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        Text(vm.menuBarText).foregroundStyle(vm.menuBarColor).monospacedDigit()
    }
}
