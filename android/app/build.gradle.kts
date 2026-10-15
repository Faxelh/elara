plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.kounandi.elara"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.kounandi.elara"
        minSdk = 26
        targetSdk = 35
        // Numéro de version = numéro de la compilation GitHub : chaque APK est plus récent que le précédent.
        val numero = (System.getenv("ELARA_BUILD") ?: System.getenv("GITHUB_RUN_NUMBER") ?: "1").toInt()
        versionCode = numero
        versionName = System.getenv("ELARA_VERSION") ?: "2026.2.0"
        resourceConfigurations += listOf("fr", "en", "ru", "es")
    }

    // Toujours la même signature : on peut installer une nouvelle version par-dessus l'ancienne
    // (sinon Android refuse : « conflit avec un paquet existant »).
    signingConfigs {
        create("elara") {
            storeFile = file("elara.keystore")
            storePassword = System.getenv("ELARA_MOT_DE_PASSE") ?: "elara-kounandi"
            keyAlias = "elara"
            keyPassword = System.getenv("ELARA_MOT_DE_PASSE") ?: "elara-kounandi"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("elara")
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("elara")
        }
    }
    // La vérification « lint » ne doit pas bloquer la compilation de la version finale.
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.fragment:fragment-ktx:1.8.5")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-ui:1.5.1")
    implementation("androidx.media3:media3-transformer:1.5.1")
    implementation("androidx.media3:media3-effect:1.5.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
