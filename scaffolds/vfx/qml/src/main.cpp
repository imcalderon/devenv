#include <QGuiApplication>
#include <QCoreApplication>
#include <QDir>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDirIterator>
#include <iostream>
#include <string>

#include <pxr/pxr.h>
#include <pxr/usd/usd/common.h>
#include <pxr/base/tf/diagnostic.h>

int main(int argc, char *argv[])
{
    std::cout << "${PROJECT_NAME} starting..." << std::endl;
    std::cout.flush();

    // Setup runtime paths relative to executable for the installer bundle
    QString appDir = QCoreApplication::applicationDirPath();
    
    // Qt platform plugins
    QString platformsPath = appDir + "/platforms";
    if (QDir(platformsPath).exists()) {
        qputenv("QT_QPA_PLATFORM_PLUGIN_PATH", platformsPath.toLocal8Bit());
    }

    // QML import paths
    QString qmlPath = appDir + "/qml";
    if (QDir(qmlPath).exists()) {
        qputenv("QML2_IMPORT_PATH", qmlPath.toLocal8Bit());
    }

    QGuiApplication app(argc, argv);

    // USD Version Check
    std::string usdVersion = std::to_string(PXR_MAJOR_VERSION) + "." + 
                             std::to_string(PXR_MINOR_VERSION) + "." + 
                             std::to_string(PXR_PATCH_VERSION);
    std::cout << "USD Version: " << usdVersion << std::endl;

    QQmlApplicationEngine engine;
    
    // Register USD version to QML
    engine.rootContext()->setContextProperty("usdVersion", QString::fromStdString(usdVersion));

    const QUrl url(QStringLiteral("qrc:/main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
