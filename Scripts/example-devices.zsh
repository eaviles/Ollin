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
# The ones that import a device library as an output they leave off unless
# asked, so they draw everything with nothing plugged in.
DRAWS_ALONE=(Recreations/VladimirBonacic/NamaFrieze Recreations/VladimirBonacic/Random63)

# What an example (`Group/Name`) is waiting for before it can run alone, or
# nothing when it needs no device.
held_back() {
  local sketch=$ROOT/Examples/$1/Sketch.swift
  local alone module named
  for alone in $DRAWS_ALONE; do
    [[ $1 == $alone ]] && { echo ""; return; }
  done
  for module in $DEVICE_MODULES; do
    grep -q "^import $module\$" $sketch && { echo "needs a device at the desk: imports $module"; return; }
  done
  for named in $DEVICE_SKETCHES; do
    [[ $1 == $named ]] && { echo "needs a device at the desk"; return; }
  done
  echo ""
}
