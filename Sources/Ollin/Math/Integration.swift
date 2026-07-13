import Foundation

/// A state a fixed-step integrator can advance: anything with vector-space
/// addition and scaling. `Vector3` conforms for the strange attractors; a
/// system with a wider state (the double pendulum's four components) conforms
/// a small struct of its own.
protocol Integrable {
    static func + (lhs: Self, rhs: Self) -> Self
    static func * (scale: Double, value: Self) -> Self
}

extension Vector3: Integrable {}

/// One fixed-step fourth-order Runge-Kutta step of an autonomous system (the
/// derivative does not depend on time): the standard weighted average of four
/// slope samples across the step. The shared motion primitive behind the
/// strange attractors and the double pendulum.
func rungeKutta4<State: Integrable>(_ state: State, step: Double,
                                    derivative: (State) -> State) -> State {
    let k1 = derivative(state)
    let k2 = derivative(state + (step / 2) * k1)
    let k3 = derivative(state + (step / 2) * k2)
    let k4 = derivative(state + step * k3)
    return state + (step / 6) * (k1 + (2.0 * k2) + (2.0 * k3) + k4)
}
