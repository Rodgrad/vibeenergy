.pragma library

function needsNvidiaSmi(devices) {
    return (devices || []).some(function(device) {
        return device.kind === "gpu" &&
            (device.source || "").indexOf("nvidia-smi") === 0 &&
            device.error === "nvidia-smi is not installed"
    })
}
