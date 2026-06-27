#pragma once

#include <qnetworkaccessmanager.h>
#include <qobject.h>
#include <qqmlengine.h>
#include <qstring.h>

namespace caelestia {

class Requests : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Requests(QObject* parent = nullptr);

    Q_INVOKABLE void get(
        const QUrl& url, QJSValue callback, QJSValue onError = QJSValue(), QJSValue headers = QJSValue()) const;
    Q_INVOKABLE void post(const QUrl& url, const QString& body, QJSValue callback,
        QJSValue onError = QJSValue(), QJSValue headers = QJSValue()) const;
    Q_INVOKABLE QString hmacSha1Base64(const QString& message, const QString& key) const;
    Q_INVOKABLE void resetCookies() const;

private:
    QNetworkAccessManager* m_manager;
};

} // namespace caelestia
