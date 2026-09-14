// The names the MQTT page's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

import OllinMQTT

// The client the page keeps reaching for. Every fragment after the opening
// listing reads or publishes on the bus the prose already connected.
let bus = MQTTClient(host: "localhost")

// What the drain section writes down when a doorbell speaks.
var lastPressAt = 0.0
