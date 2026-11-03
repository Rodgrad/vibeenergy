import QtQuick
import QtTest
import "../../plasmoid/contents/ui/GpuSetup.js" as GpuSetup

TestCase {
    name: "NvidiaSetupVisibility"
    function test_detected_nvidia_missing_utility() {
        verify(GpuSetup.needsNvidiaSmi([{kind:"gpu",source:"nvidia-smi (board power)",error:"nvidia-smi is not installed",watts:null}]))
    }
    function test_amd_does_not_show_nvidia_install() {
        verify(!GpuSetup.needsNvidiaSmi([{kind:"gpu",source:"DRM/hwmon",error:"No supported DRM power sensor exposed",watts:null}]))
        verify(!GpuSetup.needsNvidiaSmi([]))
    }
    function test_driver_errors_do_not_claim_utility_missing() {
        verify(!GpuSetup.needsNvidiaSmi([{kind:"gpu",source:"nvidia-smi (board power)",error:"Failed to communicate with NVIDIA driver",watts:null}]))
    }
    function test_existing_readings_need_no_install() {
        verify(!GpuSetup.needsNvidiaSmi([{kind:"gpu",source:"nvidia-smi (board power)",error:"",watts:25}]))
    }
}
