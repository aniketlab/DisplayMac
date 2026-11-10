package com.displaymac.client.display

import org.junit.Assert.assertEquals
import org.junit.Test

class DeviceProfileTest {

    @Test
    fun prefersFriendlySystemDeviceNameWhenNotRawModelCode() {
        val name = DeviceProfile.resolveMarketingName(
            manufacturer = "samsung",
            model = "SM-X920",
            systemDeviceName = "Studio Tablet"
        )
        assertEquals("Studio Tablet", name)
    }

    @Test
    fun mapsKnownTabletModelWhenSystemNameIsRawCode() {
        val name = DeviceProfile.resolveMarketingName(
            manufacturer = "samsung",
            model = "SM-X920",
            systemDeviceName = "SM-X920"
        )
        assertEquals("Galaxy Tab S10 Ultra", name)
    }

    @Test
    fun doesNotDuplicateManufacturerPrefixOnGenericModels() {
        val name = DeviceProfile.resolveMarketingName(
            manufacturer = "google",
            model = "Google Pixel Slate",
            systemDeviceName = null
        )
        assertEquals("Google Pixel Slate", name)
    }

    @Test
    fun prependsCapitalizedManufacturerForUnbrandedModel() {
        val name = DeviceProfile.resolveMarketingName(
            manufacturer = "lenovo",
            model = "TB371FC",
            systemDeviceName = null
        )
        assertEquals("Lenovo TB371FC", name)
    }
}
