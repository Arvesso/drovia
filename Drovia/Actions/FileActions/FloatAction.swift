import UniformTypeIdentifiers

struct FloatAction: DroviaAction {
    let id = "actions.float"
    let wheel = WheelKind.actions
    let symbol: String? = "pin"

    var title: String {
        String(localized: "Float")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        context.shelf.add(files)
        return .silent
    }
}
