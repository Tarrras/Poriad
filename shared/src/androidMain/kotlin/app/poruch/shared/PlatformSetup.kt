package app.poruch.shared
import android.content.Context
import app.poruch.data.AndroidStorage
object PlatformSetup { fun initialize(context: Context) { AndroidStorage.context=context.applicationContext } }
