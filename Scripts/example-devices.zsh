# Scripts/example-devices.zsh: which examples need something plugged in.
#
# Sourced by the scripts that run every example on their own (`media.sh`,
# `check-determinism.sh`), so a new device library is learned in one place.
# The caller sets $ROOT to the repository.

# A sketch importing one of these needs something plugged in, so it waits for
# a person at the desk with the thing in hand.
# Vision and the camera are not here: a sketch that reads a camera falls back
# to a bundled photograph or the bundled film (`--photo`), so it draws the
# real technique on a real picture with nothing plugged in.
DEVICE_MODULES=(OllinPhone OllinRecord3D OllinScreen OllinMIDI
                OllinOSC OllinSerial OllinBluetooth OllinDMX OllinLaser OllinSyphon
                OllinRoom OllinRemote OllinLink OllinHaptics OllinController
                OllinMQTT)
# The ones that need a device without importing a library for it.
DEVICE_SKETCHES=(Input/Pen Audio/Listening Audio/PlayAlong)
# The ones that import a device library and still run with nothing plugged
# in, each with what stands in for the device: the other end of a loopback on
# this Mac, a stand-in the sketch runs of its own, or an output it leaves off
# unless asked. `media.sh` writes the sentence into the example's row as
# `staged`, so a clip of a round trip says what played the far end.
typeset -A RUNS_ALONE
RUNS_ALONE=(
  Audio/Expression                        "a hand of the sketch's own plays the phrase"
  Integration/DMXLoopback                 "a receiver on this Mac reads the universe back"
  Integration/LaserPreview                "no projector: the beam's path is drawn and nothing goes out"
  Integration/MIDILoopback                "a virtual source on this Mac plays the controller"
  Integration/OSCLoopback                 "a receiver on this Mac reads the messages back"
  Integration/TUIOSurface                 "a stand-in tracker on this Mac sends the touches"
  Recreations/NickCave/Soundsuit          "a dancer of the sketch's own wears the suit"
  Recreations/VladimirBonacic/NamaFrieze  "the lamps' wire is left off unless asked"
  Recreations/VladimirBonacic/Random63    "the lamps' wire is left off unless asked"
)
# The ones that play the far end themselves but still draw nothing worth
# showing alone, each with why, which the manifest says in place of the
# device it would otherwise name.
typeset -A HELD_BECAUSE
HELD_BECAUSE=(
  Integration/LEDMapping      "the LED map samples the frames a live window shows, and an export shows it none"
  Integration/MQTTRoom        "it needs an MQTT broker running beside it"
  Integration/RoomLoopback    "it sends where the pointer is, so it waits for a hand"
  Integration/SerialLoopback  "its stand-in device prints on the wall clock, which an export outruns"
  Integration/SyphonLoopback  "Syphon serves the frames a live window shows, so an export has no inset"
  Integration/Tempo           "its clock waits for a press of play"
  Integration/Timecode        "its deck waits for a press of play"
)

# What an example (`Group/Name`) is waiting for before it can run alone, or
# nothing when it needs no device.
held_back() {
  local sketch=$ROOT/Examples/$1/Sketch.swift
  local module named
  (( ${+RUNS_ALONE[$1]} )) && { echo ""; return; }
  (( ${+HELD_BECAUSE[$1]} )) && { echo ${HELD_BECAUSE[$1]}; return; }
  for module in $DEVICE_MODULES; do
    grep -q "^import $module\$" $sketch && { echo "needs a device at the desk: imports $module"; return; }
  done
  for named in $DEVICE_SKETCHES; do
    [[ $1 == $named ]] && { echo "needs a device at the desk"; return; }
  done
  echo ""
}

# What stands in for the device when an example that imports one runs alone,
# or nothing.
stand_in() {
  echo ${RUNS_ALONE[$1]}
}
