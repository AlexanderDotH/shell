#include "requests.hpp"

#include <qjsvalueiterator.h>
#include <qloggingcategory.h>
#include <qmessageauthenticationcode.h>
#include <qnetworkaccessmanager.h>
#include <qnetworkcookiejar.h>
#include <qnetworkreply.h>
#include <qnetworkrequest.h>

Q_LOGGING_CATEGORY(lcRequests, "caelestia.requests", QtInfoMsg)

namespace caelestia {

Requests::Requests(QObject* parent)
    : QObject(parent)
    , m_manager(new QNetworkAccessManager(this)) {}

namespace {
void applyHeaders(QNetworkRequest& request, QJSValue headers) {
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    request.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
    request.setRawHeader("Cache-Control", "no-cache, no-store");
    request.setRawHeader("Pragma", "no-cache");
    request.setRawHeader("Connection", "close");

    if (headers.isObject()) {
        QJSValueIterator it(headers);
        while (it.hasNext()) {
            it.next();
            request.setRawHeader(it.name().toUtf8(), it.value().toString().toUtf8());
        }
    }
}

void connectReply(QNetworkReply* reply, QJSValue onSuccess, QJSValue onError) {
    QObject::connect(reply, &QNetworkReply::finished, [reply, onSuccess, onError]() {
        if (reply->error() == QNetworkReply::NoError) {
            onSuccess.call({ QString(reply->readAll()) });
        } else if (onError.isCallable()) {
            onError.call({ reply->errorString() });
        } else {
            qCWarning(lcRequests) << "request failed with error" << reply->errorString();
        }

        reply->deleteLater();
    });
}
} // namespace

void Requests::get(const QUrl& url, QJSValue onSuccess, QJSValue onError, QJSValue headers) const {
    if (!onSuccess.isCallable()) {
        qCWarning(lcRequests) << "get: onSuccess is not callable";
        return;
    }

    QNetworkRequest request(url);
    applyHeaders(request, headers);
    connectReply(m_manager->get(request), onSuccess, onError);
}

void Requests::post(const QUrl& url, const QString& body, QJSValue onSuccess, QJSValue onError, QJSValue headers) const {
    if (!onSuccess.isCallable()) {
        qCWarning(lcRequests) << "post: onSuccess is not callable";
        return;
    }

    QNetworkRequest request(url);
    applyHeaders(request, headers);
    connectReply(m_manager->post(request, body.toUtf8()), onSuccess, onError);
}

QString Requests::hmacSha1Base64(const QString& message, const QString& key) const {
    return QString::fromLatin1(
        QMessageAuthenticationCode::hash(message.toUtf8(), key.toUtf8(), QCryptographicHash::Sha1).toBase64());
}

void Requests::resetCookies() const {
    m_manager->setCookieJar(new QNetworkCookieJar(m_manager));
}

} // namespace caelestia
