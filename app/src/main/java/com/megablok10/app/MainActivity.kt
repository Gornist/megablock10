package com.megablok10.app

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import com.google.zxing.integration.android.IntentIntegrator
import com.megablok10.app.identity.ContactQr
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityManager

// Минимальная тёмная тема в духе общего стиля проекта — без полного
// чамферного стайлгайда, чтобы не тормозить эту часть работы.
private val LimeAccent = Color(0xFFD9FF3F)
private val AppBackground = Color(0xFF0C0C0D)
private val AppSurface = Color(0xFF151515)

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = LimeAccent,
                    background = AppBackground,
                    surface = AppSurface,
                    onPrimary = Color.Black,
                    onBackground = Color(0xFFF5F5F0),
                    onSurface = Color(0xFFF5F5F0)
                )
            ) {
                Surface(color = MaterialTheme.colorScheme.background) {
                    AppRoot()
                }
            }
        }
    }
}

@Composable
fun AppRoot() {
    val context = LocalContext.current
    var identity by remember { mutableStateOf(IdentityManager.current(context)) }

    if (identity == null) {
        SetupScreen(onCreated = { callsign, faction ->
            identity = IdentityManager.getOrCreate(context, callsign, faction)
        })
    } else {
        ProfileScreen(identity!!)
    }
}

@Composable
fun SetupScreen(onCreated: (String, String) -> Unit) {
    var callsign by remember { mutableStateOf("") }
    var faction by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center
    ) {
        Text("Создание личности", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(
            value = callsign,
            onValueChange = { callsign = it },
            label = { Text("Позывной") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = faction,
            onValueChange = { faction = it },
            label = { Text("Фракция") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = { if (callsign.isNotBlank()) onCreated(callsign, faction) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Сгенерировать ключ и QR")
        }
        Spacer(Modifier.height(8.dp))
        Text(
            "Ключевая пара генерируется один раз на этом устройстве и " +
                "остаётся идентификатором персонажа на всю игру.",
            style = MaterialTheme.typography.bodySmall
        )
    }
}

@Composable
fun ProfileScreen(identity: Identity) {
    val context = LocalContext.current
    val activity = context as Activity
    var contacts by remember { mutableStateOf(ContactStore.all(context)) }

    val scanLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val scan = IntentIntegrator.parseActivityResult(result.resultCode, result.data)
        val raw = scan?.contents ?: return@rememberLauncherForActivityResult
        ContactQr.decode(raw)?.let { contact ->
            ContactStore.add(context, contact)
            contacts = ContactStore.all(context)
        }
    }

    fun startScan() {
        val integrator = IntentIntegrator(activity)
            .setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
            .setPrompt("Наведите на QR контакта")
            .setBeepEnabled(false)
        scanLauncher.launch(integrator.createScanIntent())
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp)
    ) {
        Text(identity.callsign, style = MaterialTheme.typography.headlineSmall)
        Text(identity.faction, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.height(16.dp))

        val qrBitmap = remember(identity.publicKeyB64) {
            generateQrBitmap(ContactQr.encode(identity))
        }
        Image(
            bitmap = qrBitmap.asImageBitmap(),
            contentDescription = "QR-код контакта",
            modifier = Modifier
                .size(220.dp)
                .align(Alignment.CenterHorizontally)
        )

        Spacer(Modifier.height(20.dp))
        Button(onClick = { startScan() }, modifier = Modifier.fillMaxWidth()) {
            Text("Сканировать контакт")
        }

        Spacer(Modifier.height(20.dp))
        Text("Контакты (${contacts.size})", style = MaterialTheme.typography.titleSmall)
        LazyColumn(modifier = Modifier.padding(top = 8.dp)) {
            items(contacts) { c ->
                Column(modifier = Modifier.padding(vertical = 6.dp)) {
                    Text(c.callsign, style = MaterialTheme.typography.bodyLarge)
                    Text(c.faction, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

private fun generateQrBitmap(content: String, sizePx: Int = 512): Bitmap {
    val matrix = MultiFormatWriter().encode(content, BarcodeFormat.QR_CODE, sizePx, sizePx)
    val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.RGB_565)
    for (x in 0 until sizePx) {
        for (y in 0 until sizePx) {
            bmp.setPixel(x, y, if (matrix.get(x, y)) AndroidColor.BLACK else AndroidColor.WHITE)
        }
    }
    return bmp
}
