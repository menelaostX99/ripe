import QtQuick
import Quickshell
import qs.Commons
import "."
import "Model.js" as Model

// Keeps the timer alive from shell start, whether or not the panel has ever
// been opened, answers for it over IPC, and puts up the time's-up screen.
Item {
  id: root

  property var shell: null

  // Touching the singleton is what creates it.
  readonly property bool running: RipeStore.running

  // omarchy-shell menelaostx99.ripe.timer <toggle|start|pause|skip|reset|status>
  // omarchy-shell menelaostx99.ripe.timer phase <focus|break>
  // omarchy-shell menelaostx99.ripe.timer minutes <focus|break> <n>
  // omarchy-shell menelaostx99.ripe.timer extend <minutes>
  // omarchy-shell menelaostx99.ripe.timer mix <name>
  // omarchy-shell menelaostx99.ripe.timer option <name> <on|off>
  // omarchy-shell menelaostx99.ripe.timer <sounds | sound <name> | volume <0-100>>
  // omarchy-shell menelaostx99.ripe.timer <timesup <focus|break> | dismiss>
  ShellIpc {
    target: "menelaostx99.ripe.timer"

    function toggle(): void { RipeStore.toggle() }
    function start(): void { RipeStore.start() }
    function pause(): void { RipeStore.pause() }
    function skip(): void { RipeStore.skip() }
    function reset(): void { RipeStore.reset() }
    function phase(name: string): void { RipeStore.selectPhase(name) }
    function minutes(name: string, count: int): void { RipeStore.setMinutes(name, count) }
    function extend(count: int): void { RipeStore.extend(count) }
    function mix(name: string): void { RipeStore.loadMix(name) }
    function option(name: string, value: string): void {
      if (Model.FLAGS.indexOf(name) < 0) return
      var patch = {}
      patch[name] = value === "on" || value === "true" || value === "1"
      RipeStore.update(patch)
    }
    function sounds(): void { RipeStore.toggleAmbient() }
    function sound(name: string): void {
      if (Model.SOUNDS.indexOf(name) >= 0) RipeStore.toggleSound(name)
    }
    function volume(percent: int): void { RipeStore.update({ master: percent / 100 }) }
    function timesup(name: string): void { RipeStore.showAlert(name) }
    function dismiss(): void { RipeStore.dismissAlert() }
    function status(): string { return RipeStore.statusJson() }
  }

  // One time's-up screen per monitor, for as long as there is something to
  // acknowledge.
  Variants {
    model: RipeStore.alert !== "" ? Quickshell.screens : []
    TimesUp {}
  }
}
