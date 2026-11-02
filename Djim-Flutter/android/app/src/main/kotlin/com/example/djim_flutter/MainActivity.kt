package com.example.djim_flutter

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.djim_flutter/map_launcher"
    private val PERMISSION_REQUEST_CODE = 2001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentLocation" -> {
                    try {
                        val hasFine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                        val hasCoarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

                        if (!hasFine && !hasCoarse) {
                            // Demander la permission
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                                PERMISSION_REQUEST_CODE
                            )
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                        var bestLocation: Location? = null

                        val providers = listOf(
                            LocationManager.GPS_PROVIDER,
                            LocationManager.NETWORK_PROVIDER,
                            LocationManager.PASSIVE_PROVIDER
                        )

                        for (provider in providers) {
                            try {
                                if (locationManager.isProviderEnabled(provider)) {
                                    val loc = locationManager.getLastKnownLocation(provider)
                                    if (loc != null) {
                                        if (bestLocation == null || loc.time > bestLocation.time) {
                                            bestLocation = loc
                                        }
                                    }
                                }
                            } catch (_: SecurityException) {}
                        }

                        if (bestLocation != null) {
                            result.success(mapOf(
                                "lat" to bestLocation.latitude,
                                "lng" to bestLocation.longitude,
                                "accuracy" to bestLocation.accuracy
                            ))
                            return@setMethodCallHandler
                        }

                        // Si aucune position récente en cache, on écoute activement le GPS / Réseau
                        var returned = false
                        val handler = android.os.Handler(android.os.Looper.getMainLooper())
                        var listener: android.location.LocationListener? = null

                        listener = object : android.location.LocationListener {
                            override fun onLocationChanged(loc: Location) {
                                if (!returned) {
                                    returned = true
                                    handler.removeCallbacksAndMessages(null)
                                    listener?.let { locationManager.removeUpdates(it) }
                                    result.success(mapOf(
                                        "lat" to loc.latitude,
                                        "lng" to loc.longitude,
                                        "accuracy" to loc.accuracy
                                    ))
                                }
                            }
                            override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
                            override fun onProviderEnabled(provider: String) {}
                            override fun onProviderDisabled(provider: String) {}
                        }

                        handler.postDelayed({
                            if (!returned) {
                                returned = true
                                listener?.let { locationManager.removeUpdates(it) }
                                result.success(null)
                            }
                        }, 4000)

                        var listening = false
                        for (p in listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)) {
                            if (locationManager.isProviderEnabled(p)) {
                                try {
                                    locationManager.requestLocationUpdates(p, 0L, 0f, listener, android.os.Looper.getMainLooper())
                                    listening = true
                                } catch (_: SecurityException) {}
                            }
                        }

                        if (!listening) {
                            handler.removeCallbacksAndMessages(null)
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.error("LOCATION_ERROR", e.message, null)
                    }
                }

                "requestLocationPermission" -> {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                        PERMISSION_REQUEST_CODE
                    )
                    result.success(true)
                }

                "launchMaps" -> {
                    val destLat = call.argument<Double>("destLat")
                    val destLng = call.argument<Double>("destLng")
                    val label = call.argument<String>("label") ?: "Pharmacie"
                    val mode = call.argument<String>("mode") ?: "navigation"

                    try {
                        val intent = if (mode == "search") {
                            val encodedLabel = Uri.encode(if (label.isNotBlank()) label else "pharmacies")
                            val searchUrl = if (destLat != null && destLng != null) {
                                "https://www.google.com/maps/search/$encodedLabel/@$destLat,$destLng,15z"
                            } else {
                                "https://www.google.com/maps/search/$encodedLabel+togo"
                            }
                            val mapIntent = Intent(Intent.ACTION_VIEW, Uri.parse(searchUrl))
                            mapIntent.setPackage("com.google.android.apps.maps")
                            if (mapIntent.resolveActivity(packageManager) != null) {
                                mapIntent
                            } else {
                                Intent(Intent.ACTION_VIEW, Uri.parse(searchUrl))
                            }
                        } else if (destLat != null && destLng != null) {
                            if (mode == "view") {
                                val uri = Uri.parse("geo:$destLat,$destLng?q=$destLat,$destLng(${Uri.encode(label)})")
                                Intent(Intent.ACTION_VIEW, uri)
                            } else {
                                val navUri = Uri.parse("google.navigation:q=$destLat,$destLng")
                                val navIntent = Intent(Intent.ACTION_VIEW, navUri)
                                navIntent.setPackage("com.google.android.apps.maps")
                                if (navIntent.resolveActivity(packageManager) != null) {
                                    navIntent
                                } else {
                                    val fallbackUri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng")
                                    Intent(Intent.ACTION_VIEW, fallbackUri)
                                }
                            }
                        } else {
                            Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/maps/search/pharmacies+togo"))
                        }
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val fallback = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/maps/search/?api=1&query=$destLat,$destLng"))
                            fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(fallback)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("MAP_ERROR", e2.message, null)
                        }
                    }
                }

                "makePhoneCall" -> {
                    val phone = call.argument<String>("phoneNumber") ?: call.argument<String>("phone") ?: ""
                    val clean = phone.replace(" ", "").replace("-", "")
                    try {
                        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$clean"))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CALL_ERROR", e.message, null)
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
