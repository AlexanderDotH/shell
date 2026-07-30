#include "requests.hpp"

#include <qbytearray.h>
#include <qcoreapplication.h>
#include <qeventloop.h>
#include <qhash.h>
#include <qhostaddress.h>
#include <qjsvalue.h>
#include <qqmlcontext.h>
#include <qqmlengine.h>
#include <qtcpserver.h>
#include <qtcpsocket.h>
#include <qtimer.h>
#include <qurl.h>

#include <functional>
#include <iostream>
#include <memory>

namespace {

struct CapturedRequest {
    QByteArray method;
    QByteArray body;
    QHash<QByteArray, QByteArray> headers;
};

bool expect(bool condition, const char* message) {
    if (condition) {
        return true;
    }

    std::cerr << "FAIL: " << message << '\n';
    return false;
}

QByteArray normalisedHeaderName(const QByteArray& name) {
    return name.trimmed().toLower();
}

bool requestComplete(const QByteArray& data, qsizetype* headerEnd, qsizetype* contentLength) {
    *headerEnd = data.indexOf("\r\n\r\n");
    if (*headerEnd < 0) {
        return false;
    }

    *contentLength = 0;
    const auto lines = data.first(*headerEnd).split('\n');
    for (const auto& rawLine : lines) {
        const auto line = rawLine.trimmed();
        const auto colon = line.indexOf(':');
        if (colon < 0) {
            continue;
        }
        if (normalisedHeaderName(line.first(colon)) == "content-length") {
            bool ok = false;
            const auto value = line.sliced(colon + 1).trimmed().toLongLong(&ok);
            if (ok && value >= 0) {
                *contentLength = value;
            }
        }
    }

    return data.size() >= *headerEnd + 4 + *contentLength;
}

void parseRequest(const QByteArray& data, CapturedRequest* captured) {
    qsizetype headerEnd = 0;
    qsizetype contentLength = 0;
    if (!requestComplete(data, &headerEnd, &contentLength)) {
        return;
    }

    const auto lines = data.first(headerEnd).split('\n');
    if (!lines.isEmpty()) {
        captured->method = lines.first().trimmed().split(' ').value(0);
    }

    for (qsizetype i = 1; i < lines.size(); ++i) {
        const auto line = lines.at(i).trimmed();
        const auto colon = line.indexOf(':');
        if (colon < 0) {
            continue;
        }
        captured->headers.insert(normalisedHeaderName(line.first(colon)), line.sliced(colon + 1).trimmed());
    }

    captured->body = data.sliced(headerEnd + 4, contentLength);
}

struct JsOutcome {
    bool done = false;
    bool success = false;
    QString value;
    int statusCode = 0;
    QJSValue headers;
};

JsOutcome readOutcome(QQmlEngine& engine) {
    const auto state = engine.globalObject().property(QStringLiteral("__requestsState"));
    const auto value = state.property(QStringLiteral("outcome"));
    if (!value.isObject()) {
        return {};
    }

    return {
        .done = true,
        .success = value.property(QStringLiteral("success")).toBool(),
        .value = value.property(QStringLiteral("value")).toString(),
        .statusCode = value.property(QStringLiteral("statusCode")).toInt(),
        .headers = value.property(QStringLiteral("headers")),
    };
}

using InvokeRequest = std::function<void(QJSValue, QJSValue)>;

JsOutcome runCase(QTcpServer& server, QQmlEngine& engine, const QByteArray& response, CapturedRequest* captured,
    const InvokeRequest& invoke, bool oneArgumentCallback = false) {
    engine.globalObject().setProperty(QStringLiteral("__requestsState"), engine.newObject());

    const auto successSource =
        oneArgumentCallback
            ? QStringLiteral("(function(body) { __requestsState.outcome = { success: true, value: body, "
                             "statusCode: -1 }; })")
            : QStringLiteral("(function(body, metadata) { __requestsState.outcome = { success: true, value: body, "
                             "statusCode: metadata?.statusCode ?? -1, headers: metadata?.headers ?? ({}) }; })");
    const auto errorSource =
        QStringLiteral("(function(error, metadata) { __requestsState.outcome = { success: false, value: error, "
                       "statusCode: metadata?.statusCode ?? -1, headers: metadata?.headers ?? ({}) }; })");

    const QJSValue onSuccess = engine.evaluate(successSource);
    const QJSValue onError = engine.evaluate(errorSource);

    auto requestData = std::make_shared<QByteArray>();
    auto responded = std::make_shared<bool>(false);

    const auto connection = QObject::connect(&server, &QTcpServer::newConnection, &server, [&] {
        auto* socket = server.nextPendingConnection();
        if (!socket) {
            return;
        }

        const auto consume = [socket, requestData, responded, response, captured] {
            requestData->append(socket->readAll());

            qsizetype headerEnd = 0;
            qsizetype contentLength = 0;
            if (*responded || !requestComplete(*requestData, &headerEnd, &contentLength)) {
                return;
            }

            *responded = true;
            parseRequest(*requestData, captured);
            socket->write(response);
            socket->flush();
            QTimer::singleShot(0, socket, [socket] {
                socket->disconnectFromHost();
            });
        };

        QObject::connect(socket, &QTcpSocket::readyRead, socket, consume);
        QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        consume();
    });

    QEventLoop loop;
    QTimer poll;
    poll.setInterval(5);
    QObject::connect(&poll, &QTimer::timeout, &loop, [&] {
        if (readOutcome(engine).done) {
            loop.quit();
        }
    });

    bool timedOut = false;
    QTimer timeout;
    timeout.setSingleShot(true);
    QObject::connect(&timeout, &QTimer::timeout, &loop, [&] {
        timedOut = true;
        loop.quit();
    });

    invoke(onSuccess, onError);
    poll.start();
    timeout.start(3000);
    loop.exec();

    QObject::disconnect(connection);
    if (timedOut) {
        std::cerr << "FAIL: request timed out (received " << requestData->size()
                  << " request bytes, responded=" << (*responded ? "yes" : "no")
                  << ", server=" << server.errorString().toStdString() << ")\n";
        return {};
    }
    return readOutcome(engine);
}

QUrl localUrl(const QTcpServer& server, const QString& path) {
    return QUrl(QStringLiteral("http://127.0.0.1:%1%2").arg(server.serverPort()).arg(path));
}

} // namespace

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    QQmlEngine engine;
    caelestia::Requests requests;
    QQmlEngine::setContextForObject(&requests, engine.rootContext());

    QTcpServer server;
    bool ok = expect(server.listen(QHostAddress::LocalHost), "loopback HTTP server listens");
    if (!ok) {
        return 1;
    }

    CapturedRequest getRequest;
    const auto getResult =
        runCase(server, engine, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nX-Test: Value\r\nConnection: close\r\n\r\nOK",
            &getRequest, [&](QJSValue success, QJSValue error) {
                requests.get(localUrl(server, QStringLiteral("/get")), success, error);
            });
    ok &= expect(getResult.done && getResult.success, "GET invokes success callback");
    ok &= expect(getResult.value == QStringLiteral("OK"), "GET returns UTF-8 response body");
    ok &= expect(getResult.statusCode == 200, "GET exposes status code");
    ok &= expect(getResult.headers.property(QStringLiteral("x-test")).toString() == QStringLiteral("Value"),
        "GET normalises response header names");
    ok &= expect(getRequest.method == "GET", "GET uses the GET method");

    CapturedRequest rateLimitRequest;
    const auto rateLimitResult = runCase(server, engine,
        "HTTP/1.1 429 Too Many Requests\r\nContent-Length: 4\r\nX-RL: 0\r\nX-TTL: 12\r\nConnection: "
        "close\r\n\r\nwait",
        &rateLimitRequest, [&](QJSValue success, QJSValue error) {
            requests.get(localUrl(server, QStringLiteral("/limited")), success, error);
        });
    ok &= expect(rateLimitResult.done && !rateLimitResult.success, "non-2xx GET invokes error callback");
    ok &= expect(!rateLimitResult.value.isEmpty(), "error callback receives an error string");
    ok &= expect(rateLimitResult.statusCode == 429, "error callback exposes status code");
    ok &= expect(rateLimitResult.headers.property(QStringLiteral("x-rl")).toString() == QStringLiteral("0"),
        "error callback exposes x-rl header");
    ok &= expect(rateLimitResult.headers.property(QStringLiteral("x-ttl")).toString() == QStringLiteral("12"),
        "error callback exposes x-ttl header");

    CapturedRequest postRequest;
    const QJSValue requestHeaders =
        engine.evaluate(QStringLiteral("({ 'X-Custom': 'sent', 'Content-Type': 'text/plain' })"));
    const auto postResult = runCase(server, engine,
        "HTTP/1.1 201 Created\r\nContent-Length: 7\r\nX-Reply: posted\r\nConnection: close\r\n\r\ncreated",
        &postRequest, [&](QJSValue success, QJSValue error) {
            requests.post(
                localUrl(server, QStringLiteral("/post")), QStringLiteral("Grüße"), success, error, requestHeaders);
        });
    ok &= expect(postResult.done && postResult.success, "POST invokes success callback");
    ok &= expect(postResult.statusCode == 201, "POST exposes response metadata");
    ok &= expect(postResult.headers.property(QStringLiteral("x-reply")).toString() == QStringLiteral("posted"),
        "POST exposes response headers");
    ok &= expect(postRequest.method == "POST", "POST uses the POST method");
    ok &= expect(postRequest.body == QStringLiteral("Grüße").toUtf8(), "POST preserves UTF-8 request body");
    ok &= expect(postRequest.headers.value("x-custom") == "sent", "POST applies caller headers");

    CapturedRequest compatibilityRequest;
    const auto compatibilityResult = runCase(
        server, engine, "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nlegacy",
        &compatibilityRequest,
        [&](QJSValue success, QJSValue error) {
            requests.get(localUrl(server, QStringLiteral("/compat")), success, error);
        },
        true);
    ok &= expect(compatibilityResult.done && compatibilityResult.success, "one-argument callback remains callable");
    ok &= expect(compatibilityResult.value == QStringLiteral("legacy"), "one-argument callback receives the body");

    ok &= expect(requests.hmacSha1Base64(QStringLiteral("The quick brown fox jumps over the lazy dog"),
                     QStringLiteral("key")) == QStringLiteral("3nybhbi3iqa8ino29wqQcBydtNk="),
        "HMAC-SHA1 Base64 matches the known vector");

    return ok ? 0 : 1;
}
