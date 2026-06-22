package com.coinceeper.adl

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import java.io.File

/**
 * BroadcastReceiver برای مدیریت حذف اپلیکیشن و پاکسازی داده‌ها
 */
class UninstallReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "UninstallReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_PACKAGE_REMOVED -> {
                val packageName = intent.data?.schemeSpecificPart
                if (packageName == context.packageName) {
                    Log.d(TAG, "App uninstalled, cleaning up data...")
                    cleanupAllData(context)
                }
            }
            Intent.ACTION_PACKAGE_FULLY_REMOVED -> {
                val packageName = intent.data?.schemeSpecificPart
                if (packageName == context.packageName) {
                    Log.d(TAG, "App fully removed, performing final cleanup...")
                    performFinalCleanup(context)
                }
            }
        }
    }
    
    /**
     * پاکسازی تمام داده‌های اپلیکیشن
     */
    private fun cleanupAllData(context: Context) {
        try {
            Log.d(TAG, "Starting data cleanup...")
            
            // پاکسازی SharedPreferences
            clearSharedPreferences(context)
            
            // پاکسازی فایل‌های کش
            clearCacheFiles(context)
            
            // پاکسازی فایل‌های Documents
            clearDocumentsFiles(context)
            
            // پاکسازی External Storage
            clearExternalStorage(context)
            
            Log.d(TAG, "Data cleanup completed successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error during data cleanup: ${e.message}")
        }
    }
    
    /**
     * پاکسازی نهایی (برای اطمینان از حذف کامل)
     */
    private fun performFinalCleanup(context: Context) {
        try {
            Log.d(TAG, "Performing final cleanup...")
            
            // پاکسازی مجدد تمام داده‌ها
            cleanupAllData(context)
            
            // حذف فایل‌های باقی‌مانده
            deleteRemainingFiles(context)
            
            Log.d(TAG, "Final cleanup completed")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error during final cleanup: ${e.message}")
        }
    }
    
    /**
     * پاکسازی SharedPreferences
     */
    private fun clearSharedPreferences(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().clear().apply()
            
            // پاکسازی سایر SharedPreferences
            val allPrefs = context.getSharedPreferences("", Context.MODE_PRIVATE)
            allPrefs.edit().clear().apply()
            
            Log.d(TAG, "SharedPreferences cleared")
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing SharedPreferences: ${e.message}")
        }
    }
    
    /**
     * پاکسازی فایل‌های کش
     */
    private fun clearCacheFiles(context: Context) {
        try {
            val cacheDir = context.cacheDir
            if (cacheDir.exists()) {
                deleteDirectory(cacheDir)
                Log.d(TAG, "Cache files cleared")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing cache files: ${e.message}")
        }
    }
    
    /**
     * پاکسازی فایل‌های Documents
     */
    private fun clearDocumentsFiles(context: Context) {
        try {
            val filesDir = context.filesDir
            if (filesDir.exists()) {
                deleteDirectory(filesDir)
                Log.d(TAG, "Documents files cleared")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing documents files: ${e.message}")
        }
    }
    
    /**
     * پاکسازی External Storage
     */
    private fun clearExternalStorage(context: Context) {
        try {
            val externalFilesDir = context.getExternalFilesDir(null)
            if (externalFilesDir != null && externalFilesDir.exists()) {
                deleteDirectory(externalFilesDir)
                Log.d(TAG, "External storage cleared")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing external storage: ${e.message}")
        }
    }
    
    /**
     * حذف فایل‌های باقی‌مانده
     */
    private fun deleteRemainingFiles(context: Context) {
        try {
            // حذف فایل‌های باقی‌مانده در پوشه‌های مختلف
            val appDataDir = File(context.applicationInfo.dataDir)
            if (appDataDir.exists()) {
                deleteDirectory(appDataDir)
            }
            
            Log.d(TAG, "Remaining files deleted")
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting remaining files: ${e.message}")
        }
    }
    
    /**
     * حذف یک دایرکتوری و تمام محتویات آن
     */
    private fun deleteDirectory(directory: File) {
        if (directory.exists()) {
            val files = directory.listFiles()
            if (files != null) {
                for (file in files) {
                    if (file.isDirectory) {
                        deleteDirectory(file)
                    } else {
                        file.delete()
                    }
                }
            }
            directory.delete()
        }
    }
} 