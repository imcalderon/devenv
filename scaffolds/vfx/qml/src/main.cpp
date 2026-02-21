#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <iostream>

#include <pxr/usd/usd/common.h>
#include <pxr/base/tf/diagnostic.h>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    // USD Version Check
    std::cout << "USD Version: " << pxr::UsdGetVersion() << std::endl;

    QQmlApplicationEngine engine;
    
    // Register USD version to QML
    engine.rootContext()->setContextProperty("usdVersion", QString::fromStdString(std::to_string(pxr::UsdGetVersion())));

    const QUrl url(QStringLiteral("qrc:/main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
