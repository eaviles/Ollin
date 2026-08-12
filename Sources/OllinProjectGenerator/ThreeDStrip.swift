import SwiftUI
import Ollin
import OllinProjects

/// The 3D choices, laid along the direction of their own constraint.
///
/// The rules are a directed graph with three ranks: geometry is never blocked,
/// a finish can be blocked by its geometry, an extra by either. A vertical list
/// of radio buttons hides that direction, so the strip draws it instead:
/// geometry, then finish, then extras, left to right with arrows between, and
/// the reading order *is* the rule. What sits left of a thing can block it;
/// what sits right cannot.
///
/// It lives under the stage rather than in the inspector for two reasons: three
/// groups of chips need width to be taken in at once, and the cause then sits
/// directly under the effect, since every change recompiles what is playing.
struct ThreeDStrip: View {
    @Binding var recipe: ThreeDRecipe
    @Binding var hovered: ThreeDOption?

    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                group(.geometry, note: "pick one")
                arrow(active: travelled(into: .finish))
                group(.finish, note: "pick one")
                arrow(active: travelled(into: .extra))
                group(.extra, note: "any number")
                Spacer(minLength: 0)
            }
            reasonLine
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Groups

    private func group(_ slot: ThreeDOption.Slot, note: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(slot.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                // Whether one or many is written down rather than left to be
                // inferred from the shape of a control.
                Text(note).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(ThreeDOption.inSlot(slot)) { option in
                    chip(option)
                }
            }
        }
        .frame(width: 176, alignment: .leading)
    }

    /// The accent travels along the arrow into a group whose options something
    /// on the left is currently ruling out, so the edge is visible as a path.
    private func travelled(into slot: ThreeDOption.Slot) -> Bool {
        ThreeDOption.inSlot(slot).contains { recipe.blocker(of: $0) != nil }
    }

    private func arrow(active: Bool) -> some View {
        SwiftUI.Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            .frame(width: 26)
            .padding(.top, 22)
    }

    // MARK: - Chips

    private func chip(_ option: ThreeDOption) -> some View {
        let blocker = recipe.blocker(of: option)
        let missing = recipe.missingRequirements(of: option)
        let blocked = recipe.objection(to: option) != nil
        let chosen = recipe.chosen.contains(option.id)
        let reach = chosen ? recipe.blocks(option) : 0

        return Button { pick(option) } label: {
            HStack(spacing: 5) {
                if blocked {
                    SwiftUI.Image(systemName: "circle.slash")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Text(option.title)
                    .font(.system(size: 11, weight: chosen ? .medium : .regular))
                Spacer(minLength: 2)
                // The blocked chip names its cause, so the edge reads from both
                // ends without hovering anything.
                if let blocker {
                    Text(blocker.title)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else if !missing.isEmpty {
                    Text("needs \(missing.map(\.title.localizedLowercase).joined(separator: " + "))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else if reach > 0 {
                    Text("blocks \(reach)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(chosen ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.5)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1)
            }
            .foregroundStyle(blocked ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        // Every chip has a rule, not only the blocked ones, so hovering an
        // available option still says what it does.
        .onHover { inside in hovered = inside ? option : (hovered?.id == option.id ? nil : hovered) }
        .help(recipe.objection(to: option) ?? option.summary)
    }

    private func pick(_ option: ThreeDOption) {
        switch option.slot {
        case .geometry: recipe.geometry = option
        case .finish: recipe.finish = option
        case .extra:
            if recipe.extras.contains(option.id) {
                recipe.extras.remove(option.id)
            } else {
                recipe.extras.insert(option.id)
            }
        }
        // Changing one choice can invalidate another, so the recipe tidies
        // itself rather than sitting in a state the generator would refuse.
        recipe.settle()
    }

    // MARK: - The reason line

    /// Outside any scroll view, on purpose: in the inspector this text was
    /// clipped by the pinned Create bar, and moving it here removes that rather
    /// than working around it.
    private var reasonLine: some View {
        let option = hovered
        let objection = option.flatMap { recipe.objection(to: $0) }
        return HStack(alignment: .top, spacing: 6) {
            SwiftUI.Image(systemName: objection == nil ? "info.circle" : "circle.slash")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
            Group {
                if let option {
                    Text(option.title).font(.system(size: 10.5, weight: .medium))
                        + Text(" \u{2014} ").font(.system(size: 10.5)).foregroundColor(.secondary)
                        + Text(objection ?? option.summary).font(.system(size: 10.5)).foregroundColor(.secondary)
                } else {
                    Text("Hover a choice for what it does, or why it cannot be picked here.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            // The reference page is the authority when the two disagree, so the
            // strip says where it is.
            Link(destination: Self.combiningPage) {
                HStack(spacing: 3) {
                    Text("Combining 3D features").font(.system(size: 10))
                    SwiftUI.Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .frame(height: 30, alignment: .top)
    }

    static let combiningPage = URL(string: "https://github.com/eaviles/Ollin/blob/main/Docs/3D/Combining.md")!
}
