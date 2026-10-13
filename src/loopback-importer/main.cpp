#include <QHostAddress>
#include <QNetworkInterface>
#include <QString>

#include "xovi.h"

extern "C" {
QNetworkInterface override$_ZN17QNetworkInterface17interfaceFromNameERK7QString(
    QString const& name) {
    if (name == "usb0" || name == "usb1") {
        QString loopback("lo");
        return $_ZN17QNetworkInterface17interfaceFromNameERK7QString(&loopback);
    }
    return $_ZN17QNetworkInterface17interfaceFromNameERK7QString(&name);
}

bool override$_ZNK12QHostAddress8isGlobalEv(QHostAddress* address) {
    return address->isLoopback()
        ? true
        : $_ZNK12QHostAddress8isGlobalEv(address);
}
}
