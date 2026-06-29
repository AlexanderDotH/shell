#pragma once

#include "lyriccandidate.hpp"

#include <qhash.h>
#include <qjsonobject.h>
#include <qnetworkaccessmanager.h>
#include <qnetworkreply.h>
#include <qpointer.h>
#include <qset.h>

#include <functional>

namespace caelestia::services {

struct LyricLine {
    qreal time = 0.0;
    QString text;
};

class Lyrics : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QStringList lyrics READ lyrics NOTIFY lyricsChanged)
    Q_PROPERTY(caelestia::services::LyricsBackend::Backend backend READ backend NOTIFY backendChanged)
    Q_PROPERTY(caelestia::services::LyricsBackend::Backend preferredBackend READ preferredBackend WRITE
            setPreferredBackend NOTIFY preferredBackendChanged)
    Q_PROPERTY(
        QList<caelestia::services::LyricCandidate> lyricCandidates READ lyricCandidates NOTIFY lyricCandidatesChanged)
    Q_PROPERTY(caelestia::services::LyricCandidate selectedCandidate READ selectedCandidate WRITE setSelectedCandidate
            NOTIFY selectedCandidateChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(bool hasLyrics READ hasLyrics NOTIFY hasLyricsChanged)
    Q_PROPERTY(qreal offset READ offset WRITE setOffset NOTIFY offsetChanged)
    Q_PROPERTY(QString trackArtist READ trackArtist NOTIFY trackChanged)
    Q_PROPERTY(QString trackTitle READ trackTitle NOTIFY trackChanged)

public:
    explicit Lyrics(QObject* parent = nullptr);

    [[nodiscard]] QStringList lyrics() const;
    [[nodiscard]] LyricsBackend::Backend backend() const;
    [[nodiscard]] LyricsBackend::Backend preferredBackend() const;
    void setPreferredBackend(LyricsBackend::Backend value);
    [[nodiscard]] QList<LyricCandidate> lyricCandidates() const;
    [[nodiscard]] LyricCandidate selectedCandidate() const;
    void setSelectedCandidate(const LyricCandidate& value);
    [[nodiscard]] bool loading() const;
    [[nodiscard]] bool hasLyrics() const;
    [[nodiscard]] qreal offset() const;
    void setOffset(qreal value);
    [[nodiscard]] QString trackArtist() const;
    [[nodiscard]] QString trackTitle() const;

    [[nodiscard]] Q_INVOKABLE int indexForTime(qreal time) const;
    [[nodiscard]] Q_INVOKABLE qreal timeForIndex(int index) const;
    Q_INVOKABLE void setTrack(
        const QString& artist, const QString& title, const QString& album = {}, qreal duration = 0.0);
    Q_INVOKABLE void clearTrack();
    Q_INVOKABLE void refresh();

signals:
    void lyricsChanged();
    void backendChanged();
    void preferredBackendChanged();
    void lyricCandidatesChanged();
    void selectedCandidateChanged();
    void loadingChanged();
    void hasLyricsChanged();
    void offsetChanged();
    void trackChanged();

private:
    void setBackend(LyricsBackend::Backend value);
    void setLoading(bool value);
    void setLines(QVector<LyricLine> lines, LyricsBackend::Backend source);
    void clearLines();
    void appendCandidates(const QList<LyricCandidate>& add);
    void clearCandidates();

    void scheduleLoad();
    void doLoad();
    void cancelInFlight();
    int newRequestId();
    [[nodiscard]] bool asyncProvidersEnabled() const;
    void startAsyncAuto(int reqId);
    void clearAsyncWorkers();
    void handleAsyncWorkerDone(Lyrics* worker, int reqId);
    void finishAsyncAuto(int reqId);

    void tryLocal(int reqId);
    void tryLrclib(int reqId);
    void tryNetEase(int reqId);
    void tryDeezer(int reqId);
    void tryMusixmatch(int reqId);
    void trySpicyLyrics(int reqId);
    void chainNext(LyricsBackend::Backend just_failed, int reqId);

    void searchLrclibCandidates(int reqId);
    void searchNetEaseCandidates(int reqId);
    void searchDeezerCandidates(int reqId);
    void searchMusixmatchCandidates(int reqId);
    void searchSpicyLyricsCandidates(int reqId);

    void fetchLrclibById(const QString& id, int reqId);
    void fetchNetEaseLyricsById(const QString& id, int reqId, const LyricCandidate& candidate = {});
    void fetchDeezerLyricsById(const QString& id, int reqId, const LyricCandidate& candidate = {}, bool chainOnFailure = false);
    void fetchMusixmatchLyricsById(
        const QString& id, int reqId, const LyricCandidate& candidate = {}, bool chainOnFailure = false);
    void fetchSpicyLyricsById(const QString& id, int reqId, const LyricCandidate& candidate = {}, bool chainOnFailure = false);

    QNetworkReply* getJson(const QUrl& url, const QHash<QByteArray, QByteArray>& headers = {});
    QNetworkReply* postJson(
        const QUrl& url, const QJsonObject& payload, const QHash<QByteArray, QByteArray>& headers = {});
    void trackReply(int reqId, QNetworkReply* reply);
    void finishProviderFailure(LyricsBackend::Backend backend, int reqId, bool chainOnFailure);

    void onPreferredBackendConfigChanged();
    void onProviderConfigChanged();
    void onLyricsDirChanged();

    void loadLyricsMap();
    void persistTrackPrefs();

    [[nodiscard]] QString lyricsDir() const;
    [[nodiscard]] QString netEaseApiBase() const;
    [[nodiscard]] QString deezerArl() const;
    [[nodiscard]] QString spotifyAccessToken() const;
    [[nodiscard]] QUrl netEaseApiUrl(const QString& endpoint) const;
    [[nodiscard]] QUrl musixmatchDesktopUrl(
        const QString& endpoint, const QString& userToken, const QList<QPair<QString, QString>>& extraParams,
        const QString& signKey = {});
    void ensureMusixmatchDesktopToken(int reqId, std::function<void(const QString&)> callback);
    void ensureMusixmatchSignKey(int reqId, std::function<void(const QString&)> callback);
    void ensureSpotifyAccessToken(int reqId, std::function<void(const QString&)> callback);
    [[nodiscard]] QString lyricsMapPath() const;
    [[nodiscard]] QString trackKey() const;
    [[nodiscard]] static QString backendKey(LyricsBackend::Backend value);
    [[nodiscard]] static LyricsBackend::Backend backendFromKey(const QString& key);

    [[nodiscard]] static const QString& stateDir();
    [[nodiscard]] static const QString& cacheDir();
    [[nodiscard]] static QString cachePathFor(LyricsBackend::Backend backend, const QString& id);
    [[nodiscard]] static QString readCachedLrc(LyricsBackend::Backend backend, const QString& id);
    static void writeCachedLrc(LyricsBackend::Backend backend, const QString& id, const QString& text);

    [[nodiscard]] static QVector<LyricLine> parseLrc(const QString& text);
    [[nodiscard]] static QString tryReadLocalLrc(const QString& dir, const QString& artist, const QString& title);
    [[nodiscard]] static QString findLocalLrcRecursive(const QString& dir, const QString& artist, const QString& title);

    QNetworkAccessManager* m_nam;
    QTimer* m_loadDebounce;

    QVector<LyricLine> m_lines;
    QStringList m_lyrics;
    LyricsBackend::Backend m_backend = LyricsBackend::Auto;
    LyricsBackend::Backend m_preferredBackend = LyricsBackend::Auto;
    QList<LyricCandidate> m_candidates;
    LyricCandidate m_selected;
    bool m_loading = false;
    bool m_hasLyrics = false;
    qreal m_offset = 0.0;

    QString m_artist;
    QString m_title;
    QString m_album;
    qreal m_duration = 0.0;

    int m_currentRequestId = 0;
    QHash<int, QList<QPointer<QNetworkReply>>> m_pendingReplies;
    QList<Lyrics*> m_asyncWorkers;
    QSet<Lyrics*> m_finishedAsyncWorkers;
    int m_asyncRequestId = 0;
    bool m_asyncWorker = false;

    QString m_musixmatchDesktopGuid;
    QString m_musixmatchDesktopUserToken;
    qint64 m_musixmatchDesktopTokenExpiresAtMs = 0;
    QString m_musixmatchSignKey;
    qint64 m_musixmatchSignKeyExpiresAtMs = 0;
    QString m_spotifyAccessTokenCache;
    qint64 m_spotifyAccessTokenExpiresAtMs = 0;

    QJsonObject m_lyricsMap;
    bool m_lyricsMapLoaded = false;
    bool m_settingFromPrefs = false;
};

} // namespace caelestia::services
