/// Cache qui ne garde que ses `capacity` dernières entrées : les plus anciennes partent d'elles-mêmes.
/// Pour les pochettes, qui sinon s'accumuleraient morceau après morceau.
struct BoundedCache<Key: Hashable, Value> {
    let capacity: Int
    private var values: [Key: Value] = [:]
    /// Clés de la plus ancienne à la plus récente.
    private var order: [Key] = []

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { values.count }

    /// Écrire une entrée la rend la plus récente ; écrire nil la retire.
    subscript(key: Key) -> Value? {
        get { values[key] }
        set {
            order.removeAll { $0 == key }
            guard let newValue else {
                values[key] = nil
                return
            }
            values[key] = newValue
            order.append(key)
            if order.count > capacity { values[order.removeFirst()] = nil }
        }
    }
}
