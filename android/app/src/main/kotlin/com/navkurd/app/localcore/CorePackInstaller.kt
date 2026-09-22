package com.navkurd.app.localcore

import android.content.Context
import android.content.res.AssetManager
import android.system.Os
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class LocalCoreException(val code: String, message: String, cause: Throwable? = null) :
    IOException(message, cause)

data class InstalledCore(val packDirectory: String, val userDatabase: String, val packId: String,
    val mapArchives: Map<String, Map<String, Any>>, val mapSnapshot: Map<String, Any?>)

/**
 * Single app-private installer for the APK/AAB install-time asset pack.
 * Installation is explicitly requested by the future native composition root;
 * it never starts a second map, search owner or GPS watch in the R16 WebView.
 * All disk work runs on one I/O executor. No network operation exists here.
 */
class CorePackInstaller(context: Context) {
    private val app = context.applicationContext
    private val root = File(app.noBackupFilesDir, "nav_kurd_core")
    private val assets = app.assets
    private val pauseMapsRequested = AtomicBoolean(false)
    @Volatile private var mapDownload: CompletableFuture<Map<String, Any?>>? = null
    @Volatile private var cachedMapState: JSONObject? = null
    @Volatile private var cachedMapStatePackId: String? = null
    @Volatile var onMapSnapshot: ((Map<String, Any?>) -> Unit)? = null

    fun ensureInstalled(): CompletableFuture<InstalledCore> =
        CompletableFuture.supplyAsync({
            try {
                install()
            } catch (e: LocalCoreException) {
                throw e
            } catch (e: Exception) {
                throw LocalCoreException("core_install", "Local core installation failed: ${e.message}", e)
            }
        }, io)

    private fun install(): InstalledCore {
        mkdir(root)
        return RandomAccessFile(File(root, "install.lock"), "rw").use { lockFile ->
            lockFile.channel.lock().use installLock@{
                val manifestBytes = assets.open("$ASSET_ROOT/manifest.json", AssetManager.ACCESS_STREAMING)
                    .use { bounded(it, MANIFEST_LIMIT) }
                val manifest = parseManifest(manifestBytes)
                val manifestHash = hash(manifestBytes)
                val packId = manifest.getString("packId")
                val files = manifest.getJSONArray("files")
                val packs = File(root, "packs").also(::mkdir)
                val target = File(packs, packId)
                if (target.exists()) {
                    // An immutable published directory is never overwritten or
                    // silently replaced when corruption is found.
                    validateReady(target, manifestHash, files, readMapState(manifest).getString("status") == "ready")
                    activate(packId, manifestHash)
                    return@installLock installedCore(manifest, target)
                }
                val stage = File(root, "staging/$packId").also(::mkdir)
                var remaining = 0L
                val verified = mutableSetOf<String>()
                for (index in 0 until files.length()) {
                    val spec = files.getJSONObject(index)
                    val file = safeFile(stage, spec.getString("path"))
                    if (validFile(file, spec)) verified.add(spec.getString("path"))
                    else remaining = Math.addExact(remaining, spec.getLong("bytes"))
                }
                if (stage.usableSpace < remaining + 4L * 1024 * 1024) {
                    throw LocalCoreException("disk_full", "Insufficient app-private space for the local core pack.")
                }
                for (index in 0 until files.length()) {
                    val spec = files.getJSONObject(index)
                    val relative = spec.getString("path")
                    val file = safeFile(stage, relative)
                    if (relative in verified) continue
                    mkdir(file.parentFile!!)
                    val copying = File(file.parentFile, "${file.name}.copying")
                    val digest = MessageDigest.getInstance("SHA-256")
                    var count = 0L
                    assets.open("$ASSET_ROOT/$relative", AssetManager.ACCESS_STREAMING).use { input ->
                        FileOutputStream(copying, false).use { output ->
                            val buffer = ByteArray(COPY_BUFFER)
                            while (true) {
                                val read = input.read(buffer)
                                if (read < 0) break
                                count += read
                                if (count > spec.getLong("bytes")) {
                                    throw LocalCoreException("corrupt_core", "Oversized bundled core file: $relative")
                                }
                                digest.update(buffer, 0, read)
                                output.write(buffer, 0, read)
                            }
                            output.fd.sync()
                        }
                    }
                    if (count != spec.getLong("bytes") || hex(digest.digest()) != spec.getString("sha256")) {
                        throw LocalCoreException("corrupt_core", "Bundled file size/hash mismatch: $relative")
                    }
                    rename(copying, file)
                }
                verifyHeaders(stage)
                atomicBytes(File(stage, "manifest.json"), manifestBytes)
                val receiptFiles = JSONArray()
                for (index in 0 until files.length()) {
                    val spec = files.getJSONObject(index)
                    val file = safeFile(stage, spec.getString("path"))
                    receiptFiles.put(JSONObject().put("path", spec.getString("path"))
                        .put("bytes", file.length()).put("modified", file.lastModified()))
                }
                val receipt = JSONObject().put("manifestSha256", manifestHash).put("files", receiptFiles)
                atomicBytes(File(stage, "ready.json"), receipt.toString().toByteArray(Charsets.UTF_8))
                rename(stage, target)
                syncDirectory(stage.parentFile!!)
                activate(packId, manifestHash)
                installedCore(manifest, target)
            }
        }
    }

    private fun installedCore(manifest: JSONObject, target: File): InstalledCore {
        val snapshot = mapSnapshot(manifest)
        return InstalledCore(
            target.absolutePath,
            userDatabase(),
            manifest.getString("packId"),
            mapArchives(manifest, target, snapshot["status"] != "ready"),
            snapshot,
        )
    }

    private fun bundledManifest(): JSONObject = assets.open("$ASSET_ROOT/manifest.json", AssetManager.ACCESS_STREAMING)
        .use { parseManifest(bounded(it, MANIFEST_LIMIT)) }

    private fun mapStateFile(manifest: JSONObject) = File(root, "maps-${manifest.getString("packId")}.json")

    private fun readMapState(manifest: JSONObject): JSONObject {
        val packId = manifest.getString("packId")
        cachedMapState?.takeIf { cachedMapStatePackId == packId }?.let { return it }
        val file = mapStateFile(manifest)
        val state = if (!file.exists()) {
            JSONObject().put("packId", packId).put("status", "ready").put("error", JSONObject.NULL)
        } else JSONObject(file.inputStream().use { bounded(it, 16384) }.toString(Charsets.UTF_8))
        if (state.getString("packId") != packId ||
            state.getString("status") !in setOf("ready", "idle", "downloading", "paused", "error")) {
            throw LocalCoreException("map_state", "Invalid installed-map state.")
        }
        cachedMapStatePackId = packId
        cachedMapState = state
        return state
    }

    private fun writeMapState(manifest: JSONObject, status: String, error: String? = null) {
        val state = JSONObject().put("packId", manifest.getString("packId")).put("status", status)
            .put("error", error ?: JSONObject.NULL).put("updatedAt", System.currentTimeMillis())
        atomicBytes(mapStateFile(manifest), state.toString().toByteArray(Charsets.UTF_8))
        // The durable atomic write remains authoritative. This process-local
        // copy only avoids reopening/parsing the same journal for every 150 ms
        // progress emission and is populated strictly after fsync + rename.
        cachedMapStatePackId = manifest.getString("packId")
        cachedMapState = state
    }

    private fun mapSpecs(manifest: JSONObject): List<JSONObject> {
        val all = manifest.getJSONArray("files")
        return (0 until all.length()).map(all::getJSONObject).filter { it.getString("path") in MAP_PATHS }
    }

    /** Descriptors select one source explicitly. A damaged installed file never
     * triggers a bundled/network fallback. APK access is selected by user action. */
    private fun mapArchives(manifest: JSONObject, target: File, bundled: Boolean = readMapState(manifest).getString("status") != "ready"): Map<String, Map<String, Any>> =
        mapSpecs(manifest).associate { spec ->
            val path = spec.getString("path")
            path to if (!bundled) {
                val file = safeFile(target, path)
                if (!file.isFile || file.length() != spec.getLong("bytes")) {
                    throw LocalCoreException("corrupt_core", "Installed map size changed: $path")
                }
                mapOf("path" to file.absolutePath, "offset" to 0L, "bytes" to file.length())
            } else {
                assets.openFd("$ASSET_ROOT/$path").use { asset ->
                    if (asset.length != spec.getLong("bytes")) throw LocalCoreException("corrupt_core", "Bundled map size changed: $path")
                    val apk = ParcelFileDescriptor.dup(asset.fileDescriptor).use { fd ->
                        File(Os.readlink("/proc/self/fd/${fd.fd}")).canonicalPath
                    }
                    val allowed = listOf(app.applicationInfo.sourceDir) + (app.applicationInfo.splitSourceDirs?.toList() ?: emptyList())
                    if (allowed.none { File(it).canonicalPath == apk }) throw LocalCoreException("map_asset", "The map descriptor is not in this signed application.")
                    mapOf("path" to apk, "offset" to asset.startOffset, "bytes" to asset.length)
                }
            }
        }

    fun bundledMapArchives(): CompletableFuture<Map<String, Map<String, Any>>> = CompletableFuture.supplyAsync({
        val manifest = bundledManifest()
        mapArchives(manifest, File(root, "packs/${manifest.getString("packId")}"), true)
    }, io)

    fun currentMapArchives(): CompletableFuture<Map<String, Map<String, Any>>> = CompletableFuture.supplyAsync({
        val manifest = bundledManifest()
        mapArchives(manifest, File(root, "packs/${manifest.getString("packId")}"))
    }, io)

    private fun mapSnapshot(manifest: JSONObject): Map<String, Any?> {
        val state = readMapState(manifest)
        val target = File(root, "packs/${manifest.getString("packId")}")
        val total = mapSpecs(manifest).sumOf { it.getLong("bytes") }
        val count = mapSpecs(manifest).sumOf { spec ->
            val file = safeFile(target, spec.getString("path"))
            val partial = File(file.parentFile, "${file.name}.copying")
            (if (file.isFile) file.length() else if (partial.isFile) partial.length() else 0L).coerceIn(0, spec.getLong("bytes"))
        }
        // An interrupted extraction is resumable and does not resume itself.
        val status = state.getString("status").let { if (it == "downloading" && mapDownload == null) "paused" else it }
        val versions = manifest.getJSONObject("versions")
        return mapOf("status" to status, "downloadedBytes" to count, "totalBytes" to total,
            "progress" to count.toDouble() / total, "persisted" to true,
            "storageUsageBytes" to count, "storageQuotaBytes" to root.totalSpace,
            "storageAvailableBytes" to root.usableSpace,
            "verifiedAt" to if (status == "ready") File(target, "ready.json").lastModified() else null,
            "error" to state.optString("error").takeIf { it.isNotEmpty() && it != "null" },
            "mapDataVersion" to versions.getString("mapDataVersion"), "packVersion" to versions.getString("offlinePackVersion"))
    }

    fun snapshotMaps(): CompletableFuture<Map<String, Any?>> = CompletableFuture.supplyAsync({ mapSnapshot(bundledManifest()) }, io)

    private fun publishMapSnapshot(manifest: JSONObject): Map<String, Any?> = mapSnapshot(manifest).also { onMapSnapshot?.invoke(it) }

    @Synchronized fun downloadMaps(): CompletableFuture<Map<String, Any?>> {
        mapDownload?.let { return it }
        pauseMapsRequested.set(false)
        val result = CompletableFuture<Map<String, Any?>>()
        mapDownload = result
        io.execute {
            try {
                val manifest = bundledManifest()
                val target = File(root, "packs/${manifest.getString("packId")}")
                if (!target.isDirectory) throw LocalCoreException("core_missing", "Install the required local core first.")
                if (readMapState(manifest).getString("status") != "ready") {
                    val needed = mapSpecs(manifest).sumOf { spec ->
                        val file = safeFile(target, spec.getString("path"))
                        val partial = File(file.parentFile, "${file.name}.copying")
                        (spec.getLong("bytes") - (if (file.isFile) file.length() else partial.length())).coerceAtLeast(0)
                    }
                    if (target.usableSpace < needed + 4L * 1024 * 1024) {
                        throw LocalCoreException("offline-pack-storage-insufficient", "Insufficient space for the installed map copy.")
                    }
                    writeMapState(manifest, "downloading")
                    publishMapSnapshot(manifest)
                    for (spec in mapSpecs(manifest)) {
                        if (!copyMap(manifest, target, spec)) break
                    }
                    if (pauseMapsRequested.get()) writeMapState(manifest, "paused")
                    else {
                        verifyHeaders(target)
                        refreshReadyReceipt(manifest, target)
                        writeMapState(manifest, "ready")
                    }
                }
                result.complete(publishMapSnapshot(manifest))
            } catch (error: Exception) {
                try {
                    val manifest = bundledManifest()
                    writeMapState(manifest, "error", "${(error as? LocalCoreException)?.code ?: "map_install"}: ${error.message}")
                    publishMapSnapshot(manifest)
                } catch (recordError: Exception) { error.addSuppressed(recordError) }
                result.completeExceptionally(error)
            } finally { synchronized(this) { mapDownload = null } }
        }
        return result
    }

    /** Resume compares the persisted prefix against bundled bytes before append;
     * every successful install hashes the complete file with a bounded buffer. */
    private fun copyMap(manifest: JSONObject, target: File, spec: JSONObject): Boolean {
        val path = spec.getString("path")
        val file = safeFile(target, path)
        if (validFile(file, spec)) return true
        if (file.exists() && !file.delete()) throw LocalCoreException("map_io", "Cannot replace invalid installed map: $path")
        mkdir(file.parentFile!!)
        val partial = File(file.parentFile, "${file.name}.copying")
        val digest = MessageDigest.getInstance("SHA-256")
        var count = 0L
        var emitted = 0L
        assets.open("$ASSET_ROOT/$path", AssetManager.ACCESS_STREAMING).use { input ->
            RandomAccessFile(partial, "rw").use { output ->
                val prefixLength = output.length()
                if (prefixLength > spec.getLong("bytes")) throw LocalCoreException("map_corrupt", "Oversized partial map: $path")
                val buffer = ByteArray(COPY_BUFFER)
                val previous = ByteArray(COPY_BUFFER)
                while (true) {
                    if (pauseMapsRequested.get()) { output.fd.sync(); return false }
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (count + read > spec.getLong("bytes")) throw LocalCoreException("corrupt_core", "Oversized bundled map: $path")
                    val retained = minOf(read.toLong(), (prefixLength - count).coerceAtLeast(0)).toInt()
                    if (retained > 0) {
                        output.readFully(previous, 0, retained)
                        for (index in 0 until retained) if (previous[index] != buffer[index]) {
                            throw LocalCoreException("map_corrupt", "Partial map failed comparison with bundled data: $path")
                        }
                    }
                    if (retained < read) output.write(buffer, retained, read - retained)
                    digest.update(buffer, 0, read)
                    count += read
                    val now = android.os.SystemClock.elapsedRealtime()
                    if (now - emitted >= 150) { publishMapSnapshot(manifest); emitted = now }
                }
                output.fd.sync()
            }
        }
        if (count != spec.getLong("bytes") || hex(digest.digest()) != spec.getString("sha256")) {
            throw LocalCoreException("map_corrupt", "Installed map size/hash mismatch: $path")
        }
        rename(partial, file)
        return true
    }

    fun pauseMaps(): CompletableFuture<Map<String, Any?>> {
        pauseMapsRequested.set(true)
        return mapDownload ?: snapshotMaps()
    }

    fun deleteMaps(): CompletableFuture<Map<String, Any?>> {
        pauseMapsRequested.set(true)
        return CompletableFuture.supplyAsync({
            val manifest = bundledManifest()
            val target = File(root, "packs/${manifest.getString("packId")}")
            try {
                // Record explicit intent first, so a process death never causes
                // implicit extraction or a reader to open a half-deleted copy.
                writeMapState(manifest, "idle")
                for (spec in mapSpecs(manifest)) {
                    val file = safeFile(target, spec.getString("path"))
                    for (candidate in listOf(file, File(file.parentFile, "${file.name}.copying"))) {
                        if (candidate.exists() && !candidate.delete()) throw LocalCoreException("map_delete", "Cannot remove installed map: ${candidate.name}")
                    }
                }
                syncDirectory(File(target, "maps"))
                publishMapSnapshot(manifest)
            } catch (error: Exception) {
                writeMapState(manifest, "error", "map_delete: ${error.message}")
                publishMapSnapshot(manifest)
                throw error
            }
        }, io)
    }

    private fun refreshReadyReceipt(manifest: JSONObject, target: File) {
        val receiptFile = File(target, "ready.json")
        val receipt = JSONObject(receiptFile.inputStream().use { bounded(it, MANIFEST_LIMIT) }.toString(Charsets.UTF_8))
        val entries = receipt.getJSONArray("files")
        for (index in 0 until entries.length()) {
            val item = entries.getJSONObject(index)
            if (item.getString("path") !in MAP_PATHS) continue
            val file = safeFile(target, item.getString("path"))
            val spec = mapSpecs(manifest).single { it.getString("path") == item.getString("path") }
            if (!file.isFile || file.length() != spec.getLong("bytes")) throw LocalCoreException("map_corrupt", "Map installation is incomplete.")
            item.put("bytes", file.length()).put("modified", file.lastModified())
        }
        atomicBytes(receiptFile, receipt.toString().toByteArray(Charsets.UTF_8))
    }

    private fun userDatabase(): String = File(app.filesDir, "nav_kurd_user.sqlite").absolutePath

    private fun parseManifest(bytes: ByteArray): JSONObject {
        val manifest = JSONObject(bytes.toString(Charsets.UTF_8))
        if (manifest.getInt("schema") != 1 || manifest.getInt("minimumReader") != 1 || manifest.getInt("searchSchema") != 1) {
            throw LocalCoreException("unsupported_schema", "Unsupported core reader/catalog schema.")
        }
        val packId = manifest.getString("packId")
        if (!packId.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")) || packId.contains("..")) {
            throw LocalCoreException("invalid_manifest", "Unsafe pack identity.")
        }
        val entries = manifest.getJSONArray("files")
        val descriptors = sortedMapOf<String, JSONObject>()
        for (index in 0 until entries.length()) {
            val spec = entries.getJSONObject(index)
            val path = spec.getString("path")
            safeFile(root, path)
            if (descriptors.put(path, spec) != null || spec.getLong("bytes") < 0 ||
                !spec.getString("sha256").matches(Regex("[0-9a-f]{64}"))) {
                throw LocalCoreException("invalid_manifest", "Invalid or duplicated file descriptor: $path")
            }
        }
        val required = setOf("catalog.sqlite", "maps/kri-base.pmtiles", "maps/kri-roads.pmtiles",
            "styles/street.json", "styles/night.json", "content/asset-map.json")
        if (!descriptors.keys.containsAll(required)) throw LocalCoreException("invalid_manifest", "Required core descriptors are missing.")
        val identity = descriptors.entries.joinToString("") { (path, spec) ->
            "$path\u0000${spec.getLong("bytes")}\u0000${spec.getString("sha256")}\n"
        }
        val contentHash = hash(identity.toByteArray(Charsets.UTF_8))
        if (contentHash != manifest.getString("contentHash") ||
            packId != "${manifest.getJSONObject("versions").getString("offlinePackVersion")}-${contentHash.take(16)}") {
            throw LocalCoreException("invalid_manifest", "Pack identity disagrees with the content inventory.")
        }
        return manifest
    }

    private fun validFile(file: File, spec: JSONObject): Boolean {
        if (!file.exists()) return false
        if (!file.isFile || file.length() != spec.getLong("bytes")) return false
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(COPY_BUFFER)
            while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        }
        return hex(digest.digest()) == spec.getString("sha256")
    }

    private fun validateReady(target: File, manifestHash: String, specs: JSONArray, installedMaps: Boolean) {
        val savedManifest = File(target, "manifest.json").inputStream().use { bounded(it, MANIFEST_LIMIT) }
        val ready = JSONObject(File(target, "ready.json").inputStream().use { bounded(it, MANIFEST_LIMIT) }.toString(Charsets.UTF_8))
        if (hash(savedManifest) != manifestHash || ready.getString("manifestSha256") != manifestHash) {
            throw LocalCoreException("corrupt_core", "Installed core manifest/receipt differs from the bundled package.")
        }
        val receipt = ready.getJSONArray("files")
        if (receipt.length() != specs.length()) throw LocalCoreException("corrupt_core", "Invalid ready receipt.")
        for (index in 0 until specs.length()) {
            val spec = specs.getJSONObject(index)
            val record = receipt.getJSONObject(index)
            val path = spec.getString("path")
            if (!installedMaps && path in MAP_PATHS) continue
            val file = safeFile(target, path)
            if (record.getString("path") != path || !file.isFile || file.length() != spec.getLong("bytes") ||
                record.getLong("bytes") != file.length() || record.getLong("modified") != file.lastModified()) {
                throw LocalCoreException("corrupt_core", "Installed core file changed: $path")
            }
        }
        verifyHeaders(target, installedMaps)
    }

    private fun verifyHeaders(directory: File, installedMaps: Boolean = true) {
        RandomAccessFile(File(directory, "catalog.sqlite"), "r").use { file ->
            val header = ByteArray(100); file.readFully(header)
            val numbers = ByteBuffer.wrap(header).order(ByteOrder.BIG_ENDIAN)
            if (header.copyOfRange(0, 16).toString(Charsets.US_ASCII) != "SQLite format 3\u0000" ||
                numbers.getInt(60) != 1 || numbers.getInt(68) != 1313555282) {
                throw LocalCoreException("unsupported_catalog", "Unexpected local catalog identity/schema.")
            }
        }
        if (!installedMaps) return
        for (name in listOf("kri-base.pmtiles", "kri-roads.pmtiles")) {
            RandomAccessFile(File(directory, "maps/$name"), "r").use { file ->
                val header = ByteArray(8); file.readFully(header)
                if (header.copyOfRange(0, 7).toString(Charsets.US_ASCII) != "PMTiles" || header[7].toInt() != 3) {
                    throw LocalCoreException("unsupported_pmtiles", "Expected PMTiles v3: $name")
                }
            }
        }
    }

    private fun activate(packId: String, manifestHash: String) {
        val active = File(root, "active.json")
        val bytes = JSONObject().put("packId", packId).put("manifestSha256", manifestHash).toString().toByteArray(Charsets.UTF_8)
        // Avoid rewriting the small pointer on every normal launch.
        if (active.isFile && active.length() <= MANIFEST_LIMIT) {
            val old = active.inputStream().use { bounded(it, MANIFEST_LIMIT) }
            if (old.contentEquals(bytes)) return
        }
        atomicBytes(active, bytes)
    }

    private fun safeFile(parent: File, relative: String): File {
        if (relative.isEmpty() || relative.startsWith('/') || relative.contains('\\') || relative.contains(':') ||
            relative.contains('\u0000') || relative.split('/').any { it.isEmpty() || it == "." || it == ".." }) {
            throw LocalCoreException("invalid_manifest", "Unsafe core asset path.")
        }
        val file = File(parent, relative)
        if (file.canonicalPath != file.absolutePath || !file.canonicalPath.startsWith(parent.canonicalPath + File.separator)) {
            throw LocalCoreException("invalid_manifest", "Core asset path escapes its private directory.")
        }
        return file
    }
    private fun atomicBytes(file: File, bytes: ByteArray) {
        val temporary = File(file.parentFile, "${file.name}.writing")
        FileOutputStream(temporary, false).use { it.write(bytes); it.fd.sync() }
        rename(temporary, file)
    }
    private fun rename(from: File, to: File) {
        // Android's same-filesystem rename is atomic on the supported API 24+.
        Os.rename(from.absolutePath, to.absolutePath)
        syncDirectory(to.parentFile!!)
    }
    private fun mkdir(directory: File) {
        if (!directory.isDirectory && !directory.mkdirs()) throw LocalCoreException("core_io", "Cannot create private core directory.")
    }
    private fun syncDirectory(directory: File) {
        // Use public API 21+ flags; O_DIRECTORY is not exposed by the Android SDK.
        // Check the opened descriptor, so a path change cannot fsync a non-directory.
        val fd = Os.open(
            directory.absolutePath,
            OsConstants.O_RDONLY or OsConstants.O_CLOEXEC or OsConstants.O_NOFOLLOW,
            0,
        )
        try {
            if (!OsConstants.S_ISDIR(Os.fstat(fd).st_mode)) {
                throw LocalCoreException("core_io", "Core metadata parent is not a directory.")
            }
            Os.fsync(fd)
        } finally {
            Os.close(fd)
        }
    }
    private fun bounded(input: InputStream, maximum: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer); if (count < 0) break
            if (output.size() + count > maximum) throw LocalCoreException("manifest_size", "Core metadata exceeds its byte limit.")
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }
    private fun hash(bytes: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(bytes))
    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }

    companion object {
        private val MAP_PATHS = setOf("maps/kri-base.pmtiles", "maps/kri-roads.pmtiles")
        private const val ASSET_ROOT = "nav_kurd_core"
        private const val COPY_BUFFER = 1024 * 1024
        private const val MANIFEST_LIMIT = 2 * 1024 * 1024
        private val io = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "nav-kurd-core-io") }
    }
}
