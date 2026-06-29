#include "lyrics.hpp"

#include "../Config/config.hpp"
#include "../Config/serviceconfig.hpp"
#include "../Config/userpaths.hpp"

#include <qdatetime.h>
#include <qdiriterator.h>
#include <qfileinfo.h>
#include <qjsonarray.h>
#include <qmessageauthenticationcode.h>
#include <qnetworkcookiejar.h>
#include <qregularexpression.h>
#include <qsavefile.h>
#include <qurlquery.h>
#include <quuid.h>

#include <algorithm>
#include <cmath>
#include <functional>

Q_LOGGING_CATEGORY(lcLyrics, "caelestia.lyrics", QtInfoMsg)

namespace caelestia::services {

using Qt::StringLiterals::operator""_s;
using Qt::StringLiterals::operator""_ba;

namespace {

constexpr int kLoadDebounceMs = 50;
constexpr qreal kIndexFudge = 0.1;
constexpr qint64 kMusixmatchDesktopTokenTtlMs = 9 * 60 * 1000;
constexpr qint64 kMusixmatchSignKeyTtlMs = 8 * 60 * 60 * 1000;

const QString kMusixmatchDesktopApiRoot = u"https://apic-desktop.musixmatch.com/ws/1.1/"_s;
const QString kMusixmatchDesktopAppId = u"web-desktop-app-v1.0"_s;
const QString kMusixmatchFallbackSignKey = u"741941edc264ea6293cb9a6458103b4eda3ac8ed"_s;

[[nodiscard]] const QList<LyricsBackend::Backend>& onlineAutoProviderOrder() {
    static const QList<LyricsBackend::Backend> order = {
        LyricsBackend::LRCLIB,
        LyricsBackend::Deezer,
        LyricsBackend::Musixmatch,
        LyricsBackend::SpicyLyrics,
        LyricsBackend::NetEase,
    };
    return order;
}

[[nodiscard]] const QHash<QByteArray, QByteArray>& netEaseHeaders() {
    static const QHash<QByteArray, QByteArray> h = {
        { "User-Agent"_ba, "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"_ba },
        { "Referer"_ba, "https://music.163.com/"_ba },
    };
    return h;
}

[[nodiscard]] const QHash<QByteArray, QByteArray>& lrclibHeaders() {
    static const QHash<QByteArray, QByteArray> h = {
        { "User-Agent"_ba, "caelestia-shell (https://github.com/caelestia-dots/shell)"_ba },
    };
    return h;
}

[[nodiscard]] const QHash<QByteArray, QByteArray>& browserHeaders() {
    static const QHash<QByteArray, QByteArray> h = {
        { "User-Agent"_ba, "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"_ba },
    };
    return h;
}

[[nodiscard]] QHash<QByteArray, QByteArray> bearerHeaders(const QString& token) {
    QHash<QByteArray, QByteArray> h = browserHeaders();
    h.insert("Authorization"_ba, "Bearer "_ba + token.toUtf8());
    return h;
}

[[nodiscard]] QString joinArtists(const QString& s) {
    return s.trimmed();
}

[[nodiscard]] QString sanitizeFilenamePart(const QString& s) {
    QString out;
    out.reserve(s.size());
    for (const QChar c : s) {
        if (c == QLatin1Char('/') || c == QLatin1Char('\0')) {
            out.append(QLatin1Char('_'));
        } else {
            out.append(c);
        }
    }
    return out;
}

[[nodiscard]] bool containsCi(const QString& haystack, const QString& needle) {
    return haystack.contains(needle, Qt::CaseInsensitive);
}

[[nodiscard]] QString simplifyForMatch(QString text) {
    static const QRegularExpression featuredRegex(u"\\s*[\\(\\[]\\s*(?:feat\\.?|ft\\.?|featuring)\\s+[^\\)\\]]+[\\)\\]]\\s*"_s,
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression combiningRegex(u"\\p{Mn}"_s);
    static const QRegularExpression whitespaceRegex(u"\\s+"_s);

    text = text.toLower();
    text.replace(featuredRegex, u" "_s);
    text = text.normalized(QString::NormalizationForm_D);
    text.replace(combiningRegex, QString());
    text.replace(whitespaceRegex, u" "_s);
    return text.trimmed();
}

[[nodiscard]] QStringList splitArtistsForMatch(const QString& artist) {
    static const QRegularExpression separatorRegex(u"[,;&/|]"_s);
    static const QRegularExpression featuredRegex(u"\\s+(?:feat\\.?|ft\\.?|featuring)\\s+"_s,
        QRegularExpression::CaseInsensitiveOption);

    QStringList artists;
    for (const QString& part : artist.split(separatorRegex, Qt::SkipEmptyParts)) {
        for (const QString& subpart : part.split(featuredRegex, Qt::SkipEmptyParts)) {
            const QString simplified = simplifyForMatch(subpart);
            if (!simplified.isEmpty()) {
                artists.append(simplified);
            }
        }
    }
    return artists;
}

[[nodiscard]] QString primaryArtist(const QString& artist) {
    static const QRegularExpression separatorRegex(u"[,;&/|]"_s);
    static const QRegularExpression featuredRegex(u"\\s+(?:feat\\.?|ft\\.?|featuring)\\s+"_s,
        QRegularExpression::CaseInsensitiveOption);

    const QString first = artist.split(separatorRegex).value(0);
    const QString primary = first.split(featuredRegex).value(0).trimmed();
    return primary.isEmpty() ? artist.trimmed() : primary;
}

[[nodiscard]] qsizetype levenshteinDistance(QString a, QString b) {
    a = simplifyForMatch(a);
    b = simplifyForMatch(b);
    if (a == b) {
        return 0;
    }
    if (a.isEmpty()) {
        return b.size();
    }
    if (b.isEmpty()) {
        return a.size();
    }

    QVector<qsizetype> previous(b.size() + 1);
    for (qsizetype j = 0; j <= b.size(); ++j) {
        previous[j] = j;
    }

    for (qsizetype i = 1; i <= a.size(); ++i) {
        QVector<qsizetype> current(b.size() + 1);
        current[0] = i;
        for (qsizetype j = 1; j <= b.size(); ++j) {
            const qsizetype cost = a.at(i - 1) == b.at(j - 1) ? 0 : 1;
            current[j] = std::min({ current[j - 1] + 1, previous[j] + 1, previous[j - 1] + cost });
        }
        previous = std::move(current);
    }

    return previous[b.size()];
}

[[nodiscard]] qreal matchScore(const LyricCandidate& hit, const QString& title, const QString& artist, qreal duration) {
    const qsizetype titleMax = std::max<qsizetype>({ simplifyForMatch(title).size(), simplifyForMatch(hit.title()).size(), 1 });
    qreal score = static_cast<qreal>(levenshteinDistance(title, hit.title())) / static_cast<qreal>(titleMax);

    const QStringList requestedArtists = splitArtistsForMatch(artist);
    const QStringList hitArtists = splitArtistsForMatch(hit.artist());
    if (!requestedArtists.isEmpty() && !hitArtists.isEmpty()) {
        bool matched = false;
        for (const QString& requested : requestedArtists) {
            for (const QString& candidate : hitArtists) {
                if (requested.contains(candidate) || candidate.contains(requested)) {
                    matched = true;
                    break;
                }
            }
            if (matched) {
                break;
            }
        }
        score += matched ? -0.35 : 0.55;
    }

    if (duration > 0 && hit.duration() > 0) {
        score += std::min<qreal>(0.5, std::abs(duration - hit.duration()) / std::max<qreal>(duration, 1.0));
    }

    return score;
}

[[nodiscard]] LyricCandidate pickBestCandidate(
    const QList<LyricCandidate>& hits, const QString& title, const QString& artist, qreal duration) {
    if (hits.isEmpty()) {
        return {};
    }

    LyricCandidate best = hits.first();
    qreal bestScore = matchScore(best, title, artist, duration);
    for (qsizetype i = 1; i < hits.size(); ++i) {
        const qreal score = matchScore(hits.at(i), title, artist, duration);
        if (score < bestScore) {
            best = hits.at(i);
            bestScore = score;
        }
    }
    return best;
}

[[nodiscard]] bool artistMatches(const QString& currentArtist, const QString& candidateArtist) {
    if (currentArtist.isEmpty() || candidateArtist.isEmpty()) {
        return true;
    }
    return containsCi(currentArtist, candidateArtist) || containsCi(candidateArtist, currentArtist);
}

[[nodiscard]] QString deezerArtistName(const QJsonObject& track) {
    return track.value(u"artist"_s).toObject().value(u"name"_s).toString();
}

[[nodiscard]] QString deezerAlbumName(const QJsonObject& track) {
    return track.value(u"album"_s).toObject().value(u"title"_s).toString();
}

[[nodiscard]] qreal deezerDurationSeconds(const QJsonObject& track) {
    return track.value(u"duration"_s).toDouble();
}

[[nodiscard]] QStringList spotifyArtistNames(const QJsonObject& track) {
    const QJsonArray artists = track.value(u"artists"_s).toArray();
    QStringList names;
    names.reserve(artists.size());
    for (const auto& artist : artists) {
        const QString name = artist.toObject().value(u"name"_s).toString();
        if (!name.isEmpty()) {
            names.append(name);
        }
    }
    return names;
}

[[nodiscard]] QString spotifyAlbumName(const QJsonObject& track) {
    return track.value(u"album"_s).toObject().value(u"name"_s).toString();
}

[[nodiscard]] qreal spotifyDurationSeconds(const QJsonObject& track) {
    return track.value(u"duration_ms"_s).toDouble() / 1000.0;
}

[[nodiscard]] QStringList netEaseArtistNames(const QJsonObject& song) {
    const QJsonArray artists = song.value(u"artists"_s).toArray().isEmpty()
        ? song.value(u"ar"_s).toArray()
        : song.value(u"artists"_s).toArray();

    QStringList names;
    names.reserve(artists.size());
    for (const auto& artist : artists) {
        const QString name = artist.toObject().value(u"name"_s).toString();
        if (!name.isEmpty()) {
            names.append(name);
        }
    }
    return names;
}

[[nodiscard]] QString netEaseAlbumName(const QJsonObject& song) {
    const QString legacy = song.value(u"album"_s).toObject().value(u"name"_s).toString();
    if (!legacy.isEmpty()) {
        return legacy;
    }
    return song.value(u"al"_s).toObject().value(u"name"_s).toString();
}

[[nodiscard]] qreal netEaseDurationSeconds(const QJsonObject& song) {
    const qreal value =
        song.contains(u"duration"_s) ? song.value(u"duration"_s).toDouble() : song.value(u"dt"_s).toDouble();
    return value > 1000 ? value / 1000.0 : value;
}

[[nodiscard]] QList<LyricCandidate> parseMusixmatchCandidates(const QJsonDocument& doc) {
    const QJsonObject message = doc.object().value(u"message"_s).toObject();
    const int status = message.value(u"header"_s).toObject().value(u"status_code"_s).toInt(-1);
    if (status != 200) {
        return {};
    }

    const QJsonArray trackList = message.value(u"body"_s).toObject().value(u"track_list"_s).toArray();
    QList<LyricCandidate> hits;
    hits.reserve(trackList.size());
    for (const auto& value : trackList) {
        const QJsonObject track = value.toObject().value(u"track"_s).toObject();
        const QString id = QString::number(static_cast<qint64>(track.value(u"track_id"_s).toDouble()));
        if (id.isEmpty() || id == u"0"_s) {
            continue;
        }
        hits.append(LyricCandidate(LyricsBackend::Musixmatch, id, track.value(u"track_name"_s).toString(),
            track.value(u"artist_name"_s).toString(), track.value(u"album_name"_s).toString(),
            track.value(u"track_length"_s).toDouble()));
    }
    return hits;
}

[[nodiscard]] QString hmacSha1Base64(const QString& message, const QString& key) {
    return QString::fromLatin1(
        QMessageAuthenticationCode::hash(message.toUtf8(), key.toUtf8(), QCryptographicHash::Sha1).toBase64());
}

[[nodiscard]] QString percentEncode(const QString& value) {
    return QString::fromLatin1(QUrl::toPercentEncoding(value));
}

[[nodiscard]] QString buildQuery(const QList<QPair<QString, QString>>& pairs) {
    QStringList parts;
    parts.reserve(pairs.size());
    for (const auto& pair : pairs) {
        if (pair.second.isEmpty()) {
            continue;
        }
        parts.append(u"%1=%2"_s.arg(percentEncode(pair.first), percentEncode(pair.second)));
    }
    return parts.join(QLatin1Char('&'));
}

[[nodiscard]] QString resolveMusixmatchScriptUrl(const QString& href) {
    const QString value = href.trimmed();
    if (value.startsWith(u"http://"_s) || value.startsWith(u"https://"_s)) {
        return value;
    }
    if (value.startsWith(u"//"_s)) {
        return u"https:"_s + value;
    }
    if (value.startsWith(QLatin1Char('/'))) {
        return u"https://www.musixmatch.com"_s + value;
    }
    return value.isEmpty() ? QString() : u"https:"_s + value;
}

[[nodiscard]] QString musixmatchScriptUrlFromCommunityPage(const QString& html) {
    static const QRegularExpression scriptRegex(u"[\"']([^\"']*common-[^\"']*)[\"']"_s);
    const auto match = scriptRegex.match(html);
    return match.hasMatch() ? resolveMusixmatchScriptUrl(match.captured(1)) : QString();
}

[[nodiscard]] QString formatLrcTimestamp(qreal seconds) {
    const int totalMs = qMax(0, qRound(seconds * 1000.0));
    const int minutes = totalMs / 60000;
    const int rem = totalMs % 60000;
    const int secs = rem / 1000;
    const int centis = (rem % 1000) / 10;
    return u"[%1:%2.%3]"_s.arg(minutes, 2, 10, QLatin1Char('0'))
        .arg(secs, 2, 10, QLatin1Char('0'))
        .arg(centis, 2, 10, QLatin1Char('0'));
}

[[nodiscard]] QString linesToLrc(const QVector<LyricLine>& lines) {
    QString out;
    for (const auto& line : lines) {
        out += formatLrcTimestamp(line.time);
        out += line.text;
        out += QLatin1Char('\n');
    }
    return out;
}

[[nodiscard]] QVector<LyricLine> parseDeezerLines(const QJsonArray& syncLines) {
    QVector<LyricLine> lines;
    lines.reserve(syncLines.size());
    for (const auto& value : syncLines) {
        const QJsonObject line = value.toObject();
        QString text = line.value(u"line"_s).toString().trimmed();
        if (text.isEmpty()) {
            text = QStringLiteral("♪");
        }
        const qreal milliseconds = line.value(u"milliseconds"_s).toDouble(-1.0);
        if (milliseconds >= 0.0) {
            lines.append(LyricLine{ milliseconds / 1000.0, text });
        }
    }
    return lines;
}

[[nodiscard]] QString spicySyllableText(const QJsonArray& syllables) {
    QString text;
    for (qsizetype i = 0; i < syllables.size(); ++i) {
        const QJsonObject syllable = syllables.at(i).toObject();
        text += syllable.value(u"Text"_s).toString();
        if (i < syllables.size() - 1 && !syllable.value(u"IsPartOfWord"_s).toBool()) {
            text += QLatin1Char(' ');
        }
    }
    return text.trimmed();
}

[[nodiscard]] QVector<LyricLine> parseSpicyLyricsObject(const QJsonObject& lyrics) {
    const QString type = lyrics.value(u"Type"_s).toString();
    QVector<LyricLine> lines;

    if (type == u"Line"_s) {
        const QJsonArray content = lyrics.value(u"Content"_s).toArray();
        lines.reserve(content.size());
        for (const auto& value : content) {
            const QJsonObject line = value.toObject();
            if (line.value(u"Type"_s).toString() != u"Vocal"_s) {
                continue;
            }
            const QString text = line.value(u"Text"_s).toString().trimmed();
            if (!text.isEmpty()) {
                lines.append(LyricLine{ line.value(u"StartTime"_s).toDouble(), text });
            }
        }
        return lines;
    }

    if (type == u"Syllable"_s) {
        const QJsonArray content = lyrics.value(u"Content"_s).toArray();
        lines.reserve(content.size());
        for (const auto& value : content) {
            const QJsonObject line = value.toObject();
            if (line.value(u"Type"_s).toString() != u"Vocal"_s) {
                continue;
            }
            const QJsonObject lead = line.value(u"Lead"_s).toObject();
            const QJsonArray syllables = lead.value(u"Syllables"_s).toArray();
            const QString text = spicySyllableText(syllables);
            if (text.isEmpty()) {
                continue;
            }
            qreal start = lead.value(u"StartTime"_s).toDouble(-1.0);
            if (start < 0.0 && !syllables.isEmpty()) {
                start = syllables.first().toObject().value(u"StartTime"_s).toDouble();
            }
            lines.append(LyricLine{ qMax(0.0, start), text });
        }
    }

    return lines;
}

[[nodiscard]] QJsonValue unpackSpicyPayload(const QJsonValue& payload) {
    const QJsonArray packed = payload.toArray();
    if (packed.size() != 2) {
        return payload;
    }

    const QJsonArray values = packed.at(0).toArray();
    const QJsonArray stream = packed.at(1).toArray();
    qsizetype cursor = 0;

    auto readStream = [&]() -> QJsonValue {
        if (cursor >= stream.size()) {
            return {};
        }
        return stream.at(cursor++);
    };

    auto resolvePointer = [&](int ptr) -> QJsonValue {
        if (ptr < 0 || ptr >= values.size()) {
            return {};
        }
        return values.at(ptr);
    };

    std::function<QJsonValue(int)> decode = [&](int depth) -> QJsonValue {
        if (depth > 512) {
            return {};
        }
        const QJsonValue opValue = readStream();
        if (!opValue.isDouble()) {
            return {};
        }
        const int op = static_cast<int>(opValue.toDouble());
        if (op >= 0) {
            return resolvePointer(op);
        }

        switch (op) {
        case -1: {
            const int numKeys = static_cast<int>(readStream().toDouble());
            QStringList keys;
            keys.reserve(numKeys);
            for (int i = 0; i < numKeys; ++i) {
                keys.append(resolvePointer(static_cast<int>(readStream().toDouble())).toString());
            }
            QJsonObject obj;
            for (const QString& key : std::as_const(keys)) {
                if (key == u"__proto__"_s || key == u"constructor"_s || key == u"prototype"_s) {
                    return {};
                }
                obj.insert(key, decode(depth + 1));
            }
            return obj;
        }
        case -2: {
            const int numItems = static_cast<int>(readStream().toDouble());
            QJsonArray arr;
            for (int i = 0; i < numItems; ++i) {
                arr.append(decode(depth + 1));
            }
            return arr;
        }
        case -3: {
            const int numItems = static_cast<int>(readStream().toDouble());
            const int numKeys = static_cast<int>(readStream().toDouble());
            QStringList keys;
            keys.reserve(numKeys);
            for (int i = 0; i < numKeys; ++i) {
                keys.append(resolvePointer(static_cast<int>(readStream().toDouble())).toString());
            }
            QJsonArray arr;
            for (int i = 0; i < numItems; ++i) {
                QJsonObject obj;
                for (const QString& key : std::as_const(keys)) {
                    obj.insert(key, decode(depth + 1));
                }
                arr.append(obj);
            }
            return arr;
        }
        case -4:
            return QJsonArray();
        case -5: {
            QJsonArray arr;
            arr.append(decode(depth + 1));
            return arr;
        }
        case -6:
            return QJsonObject();
        default:
            return {};
        }
    };

    return decode(0);
}

} // namespace

Lyrics::Lyrics(QObject* parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_loadDebounce(new QTimer(this)) {
    m_musixmatchSignKey = kMusixmatchFallbackSignKey;

    m_loadDebounce->setSingleShot(true);
    m_loadDebounce->setInterval(kLoadDebounceMs);
    QObject::connect(m_loadDebounce, &QTimer::timeout, this, &Lyrics::doLoad);

    const auto* cfg = config::GlobalConfig::instance();
    const auto* svcCfg = cfg->services();
    const auto* paths = cfg->paths();

    m_preferredBackend = backendFromKey(svcCfg->lyricsBackend());

    QObject::connect(
        svcCfg, &config::ServiceConfig::lyricsBackendChanged, this, &Lyrics::onPreferredBackendConfigChanged);
    QObject::connect(
        svcCfg, &config::ServiceConfig::lyricsAsyncProvidersChanged, this, &Lyrics::onProviderConfigChanged);
    QObject::connect(
        svcCfg, &config::ServiceConfig::lyricsNetEaseApiBaseChanged, this, &Lyrics::onProviderConfigChanged);
    QObject::connect(svcCfg, &config::ServiceConfig::lyricsDeezerArlChanged, this, &Lyrics::onProviderConfigChanged);
    QObject::connect(
        svcCfg, &config::ServiceConfig::lyricsSpotifyAccessTokenChanged, this, &Lyrics::onProviderConfigChanged);
    QObject::connect(
        svcCfg, &config::ServiceConfig::lyricsSpotifyClientIdChanged, this, &Lyrics::onProviderConfigChanged);
    QObject::connect(
        svcCfg, &config::ServiceConfig::lyricsSpotifyClientSecretChanged, this, &Lyrics::onProviderConfigChanged);
    QObject::connect(paths, &config::UserPaths::lyricsDirChanged, this, &Lyrics::onLyricsDirChanged);

    loadLyricsMap();
}

QStringList Lyrics::lyrics() const {
    return m_lyrics;
}

LyricsBackend::Backend Lyrics::backend() const {
    return m_backend;
}

LyricsBackend::Backend Lyrics::preferredBackend() const {
    return m_preferredBackend;
}

void Lyrics::setPreferredBackend(LyricsBackend::Backend value) {
    if (m_preferredBackend == value) {
        return;
    }
    m_preferredBackend = value;
    emit preferredBackendChanged();

    auto* const svcCfg = config::GlobalConfig::instance()->services();
    const QString key = backendKey(value);
    if (svcCfg->lyricsBackend() != key) {
        svcCfg->set_lyricsBackend(key);
    }

    scheduleLoad();
}

QList<LyricCandidate> Lyrics::lyricCandidates() const {
    return m_candidates;
}

LyricCandidate Lyrics::selectedCandidate() const {
    return m_selected;
}

void Lyrics::setSelectedCandidate(const LyricCandidate& value) {
    if (m_selected == value) {
        return;
    }
    m_selected = value;
    emit selectedCandidateChanged();

    if (!value.isValid()) {
        return;
    }

    const auto b = value.backend();
    setBackend(b);
    setLoading(true);

    cancelInFlight();
    const int reqId = newRequestId();

    if (b != LyricsBackend::Auto && b != LyricsBackend::Local) {
        const QString cached = readCachedLrc(b, value.id());
        if (!cached.isEmpty()) {
            const auto lines = parseLrc(cached);
            if (!lines.isEmpty()) {
                setLines(lines, b);
                setLoading(false);
                if (!m_settingFromPrefs) {
                    persistTrackPrefs();
                }
                return;
            }
        }
    }

    if (b == LyricsBackend::LRCLIB) {
        fetchLrclibById(value.id(), reqId);
    } else if (b == LyricsBackend::NetEase) {
        fetchNetEaseLyricsById(value.id(), reqId);
    } else if (b == LyricsBackend::Deezer) {
        fetchDeezerLyricsById(value.id(), reqId);
    } else if (b == LyricsBackend::Musixmatch) {
        fetchMusixmatchLyricsById(value.id(), reqId);
    } else if (b == LyricsBackend::SpicyLyrics) {
        fetchSpicyLyricsById(value.id(), reqId);
    } else if (b == LyricsBackend::Local) {
        // For local, the id is the file path. Read directly.
        QFile f(value.id());
        if (f.open(QIODevice::ReadOnly)) {
            const QString text = QString::fromUtf8(f.readAll());
            setLines(parseLrc(text), LyricsBackend::Local);
            setLoading(false);
        } else {
            qCWarning(lcLyrics) << "selectedCandidate: cannot open local file" << value.id();
            setLoading(false);
        }
    }

    if (!m_settingFromPrefs) {
        persistTrackPrefs();
    }
}

bool Lyrics::loading() const {
    return m_loading;
}

bool Lyrics::hasLyrics() const {
    return m_hasLyrics;
}

qreal Lyrics::offset() const {
    return m_offset;
}

void Lyrics::setOffset(qreal value) {
    if (qFuzzyCompare(m_offset, value)) {
        return;
    }
    m_offset = value;
    emit offsetChanged();

    if (!m_settingFromPrefs) {
        persistTrackPrefs();
    }
}

QString Lyrics::trackArtist() const {
    return m_artist;
}

QString Lyrics::trackTitle() const {
    return m_title;
}

int Lyrics::indexForTime(qreal time) const {
    if (m_lines.isEmpty()) {
        return -1;
    }
    const qreal target = time - m_offset + kIndexFudge;
    qsizetype lo = 0;
    qsizetype hi = m_lines.size();
    while (lo < hi) {
        const qsizetype mid = lo + (hi - lo) / 2;
        if (m_lines.at(mid).time <= target) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return static_cast<int>(lo - 1);
}

qreal Lyrics::timeForIndex(int index) const {
    if (index < 0 || index >= m_lines.size()) {
        return -1.0;
    }
    return m_lines.at(index).time + m_offset;
}

void Lyrics::setTrack(const QString& artist, const QString& title, const QString& album, qreal duration) {
    const QString a = artist.trimmed();
    const QString t = title.trimmed();

    if (a == m_artist && t == m_title && album == m_album && qFuzzyCompare(duration + 1.0, m_duration + 1.0)) {
        return;
    }

    m_artist = a;
    m_title = t;
    m_album = album;
    m_duration = duration;
    emit trackChanged();

    scheduleLoad();
}

void Lyrics::clearTrack() {
    cancelInFlight();
    m_artist.clear();
    m_title.clear();
    m_album.clear();
    m_duration = 0.0;
    emit trackChanged();

    clearCandidates();
    clearLines();
    setLoading(false);
}

void Lyrics::refresh() {
    scheduleLoad();
}

void Lyrics::setBackend(LyricsBackend::Backend value) {
    if (m_backend == value) {
        return;
    }
    m_backend = value;
    emit backendChanged();
}

void Lyrics::setLoading(bool value) {
    if (m_loading == value) {
        return;
    }
    m_loading = value;
    emit loadingChanged();
}

void Lyrics::setLines(QVector<LyricLine> lines, LyricsBackend::Backend source) {
    std::sort(lines.begin(), lines.end(), [](const LyricLine& a, const LyricLine& b) {
        return a.time < b.time;
    });

    m_lines = std::move(lines);
    QStringList list;
    list.reserve(m_lines.size());
    for (const auto& l : std::as_const(m_lines)) {
        list.append(l.text);
    }
    m_lyrics = std::move(list);

    setBackend(source);
    emit lyricsChanged();

    const auto hasLyrics = !m_lines.isEmpty();
    if (hasLyrics != m_hasLyrics) {
        m_hasLyrics = hasLyrics;
        emit hasLyricsChanged();
    }
}

void Lyrics::clearLines() {
    // Doesn't actually clear lines, set a flag instead so anims can run
    m_hasLyrics = false;
    emit hasLyricsChanged();
}

void Lyrics::appendCandidates(const QList<LyricCandidate>& add) {
    if (add.isEmpty()) {
        return;
    }
    bool changed = false;
    for (const auto& c : add) {
        if (!m_candidates.contains(c)) {
            m_candidates.append(c);
            changed = true;
        }
    }
    if (changed) {
        emit lyricCandidatesChanged();
    }
}

void Lyrics::clearCandidates() {
    if (m_candidates.isEmpty()) {
        return;
    }
    m_candidates.clear();
    emit lyricCandidatesChanged();
}

void Lyrics::scheduleLoad() {
    m_loadDebounce->start();
}

int Lyrics::newRequestId() {
    return ++m_currentRequestId;
}

bool Lyrics::asyncProvidersEnabled() const {
    return config::GlobalConfig::instance()->services()->lyricsAsyncProviders();
}

void Lyrics::startAsyncAuto(int reqId) {
    if (reqId != m_currentRequestId) {
        return;
    }

    setBackend(LyricsBackend::Auto);
    clearAsyncWorkers();

    m_asyncRequestId = reqId;
    for (const auto backend : onlineAutoProviderOrder()) {
        auto* worker = new Lyrics(this);
        worker->m_asyncWorker = true;
        worker->m_settingFromPrefs = true;
        worker->m_preferredBackend = backend;
        worker->m_artist = m_artist;
        worker->m_title = m_title;
        worker->m_album = m_album;
        worker->m_duration = m_duration;

        m_asyncWorkers.append(worker);
        QObject::connect(worker, &Lyrics::loadingChanged, this, [this, worker, reqId] {
            if (worker->loading()) {
                return;
            }
            handleAsyncWorkerDone(worker, reqId);
        });
    }

    for (auto* worker : std::as_const(m_asyncWorkers)) {
        if (worker) {
            worker->doLoad();
        }
    }
}

void Lyrics::clearAsyncWorkers() {
    if (m_asyncWorkers.isEmpty()) {
        return;
    }

    for (auto* worker : std::as_const(m_asyncWorkers)) {
        if (!worker) {
            continue;
        }
        QObject::disconnect(worker, nullptr, this, nullptr);
        worker->m_loadDebounce->stop();
        worker->cancelInFlight();
        worker->deleteLater();
    }

    m_asyncWorkers.clear();
    m_finishedAsyncWorkers.clear();
    m_asyncRequestId = 0;
}

void Lyrics::handleAsyncWorkerDone(Lyrics* worker, int reqId) {
    if (reqId != m_currentRequestId || reqId != m_asyncRequestId || !m_asyncWorkers.contains(worker)) {
        return;
    }
    if (m_finishedAsyncWorkers.contains(worker)) {
        return;
    }

    m_finishedAsyncWorkers.insert(worker);
    if (m_finishedAsyncWorkers.size() < m_asyncWorkers.size()) {
        return;
    }

    finishAsyncAuto(reqId);
}

void Lyrics::finishAsyncAuto(int reqId) {
    if (reqId != m_currentRequestId || reqId != m_asyncRequestId) {
        return;
    }

    Lyrics* winner = nullptr;
    for (auto* worker : std::as_const(m_asyncWorkers)) {
        if (worker && worker->m_hasLyrics && !worker->m_lines.isEmpty()) {
            winner = worker;
            break;
        }
    }

    if (winner) {
        const auto lines = winner->m_lines;
        const auto backend = winner->m_backend;
        const auto candidates = winner->m_candidates;
        const auto selected = winner->m_selected;

        appendCandidates(candidates);
        setLines(lines, backend);
        if (selected.isValid()) {
            appendCandidates({ selected });
            m_selected = selected;
            emit selectedCandidateChanged();
            persistTrackPrefs();
        }
    }

    setLoading(false);
    clearAsyncWorkers();
}

void Lyrics::cancelInFlight() {
    ++m_currentRequestId;
    m_loadDebounce->stop();
    clearAsyncWorkers();

    for (auto it = m_pendingReplies.begin(); it != m_pendingReplies.end(); ++it) {
        for (auto& ptr : it.value()) {
            if (auto* reply = ptr.data()) {
                reply->abort();
                reply->deleteLater();
            }
        }
    }
    m_pendingReplies.clear();
}

void Lyrics::trackReply(int reqId, QNetworkReply* reply) {
    if (!reply) {
        return;
    }
    m_pendingReplies[reqId].append(QPointer<QNetworkReply>(reply));
}

void Lyrics::doLoad() {
    if (m_artist.isEmpty() && m_title.isEmpty()) {
        cancelInFlight();
        clearLines();
        clearCandidates();
        setLoading(false);
        return;
    }

    cancelInFlight();
    const int reqId = newRequestId();

    setLoading(true);
    clearLines();
    clearCandidates();

    LyricCandidate restored;

    if (!m_asyncWorker) {
        // Restore per-track prefs (offset, last-selected backend/id)
        m_settingFromPrefs = true;
        const QJsonObject saved = m_lyricsMap.value(trackKey()).toObject();
        setOffset(saved.value(u"offset"_s).toDouble(0.0));
        const QString savedBackendKey = saved.value(u"backend"_s).toString();
        const QString savedId = saved.value(u"id"_s).toString();
        if (!savedBackendKey.isEmpty() && !savedId.isEmpty()) {
            restored = LyricCandidate(backendFromKey(savedBackendKey), savedId, m_title, m_artist, m_album, m_duration);
        }
        m_settingFromPrefs = false;

        // Always populate online candidates for the picker, regardless of preferred backend
        searchLrclibCandidates(reqId);
        searchDeezerCandidates(reqId);
        searchMusixmatchCandidates(reqId);
        searchSpicyLyricsCandidates(reqId);
        searchNetEaseCandidates(reqId);

        if (restored.isValid()) {
            // Honor saved selection for this track
            m_settingFromPrefs = true;
            setSelectedCandidate(restored);
            m_settingFromPrefs = false;
            return;
        }
    }

    // Primary attempt by preferred backend
    switch (m_preferredBackend) {
    case LyricsBackend::Local:
        tryLocal(reqId);
        break;
    case LyricsBackend::LRCLIB:
        tryLrclib(reqId);
        break;
    case LyricsBackend::NetEase:
        tryNetEase(reqId);
        break;
    case LyricsBackend::Deezer:
        tryDeezer(reqId);
        break;
    case LyricsBackend::Musixmatch:
        tryMusixmatch(reqId);
        break;
    case LyricsBackend::SpicyLyrics:
        trySpicyLyrics(reqId);
        break;
    case LyricsBackend::Auto:
    default:
        if (!m_asyncWorker && asyncProvidersEnabled()) {
            startAsyncAuto(reqId);
        } else {
            tryLrclib(reqId);
        }
        break;
    }
}

void Lyrics::chainNext(LyricsBackend::Backend just_failed, int reqId) {
    if (m_preferredBackend != LyricsBackend::Auto) {
        // Non-auto modes don't chain
        setLoading(false);
        return;
    }
    switch (just_failed) {
    case LyricsBackend::Local:
        tryLrclib(reqId);
        return;
    case LyricsBackend::LRCLIB:
        tryDeezer(reqId);
        return;
    case LyricsBackend::Deezer:
        tryMusixmatch(reqId);
        return;
    case LyricsBackend::Musixmatch:
        trySpicyLyrics(reqId);
        return;
    case LyricsBackend::SpicyLyrics:
        tryNetEase(reqId);
        return;
    case LyricsBackend::NetEase:
    default:
        setLoading(false);
        return;
    }
}

void Lyrics::tryLocal(int reqId) {
    if (reqId != m_currentRequestId) {
        return;
    }

    setBackend(LyricsBackend::Local);

    const QString dir = lyricsDir();
    if (dir.isEmpty()) {
        chainNext(LyricsBackend::Local, reqId);
        return;
    }

    const QString direct = tryReadLocalLrc(dir, m_artist, m_title);
    if (!direct.isEmpty()) {
        QFile f(direct);
        if (f.open(QIODevice::ReadOnly)) {
            const QString text = QString::fromUtf8(f.readAll());
            const auto lines = parseLrc(text);
            if (!lines.isEmpty()) {
                setLines(lines, LyricsBackend::Local);
                appendCandidates(
                    { LyricCandidate(LyricsBackend::Local, direct, m_title, m_artist, m_album, m_duration) });
                m_selected = LyricCandidate(LyricsBackend::Local, direct, m_title, m_artist, m_album, m_duration);
                emit selectedCandidateChanged();
                if (!m_settingFromPrefs) {
                    persistTrackPrefs();
                }
                setLoading(false);
                return;
            }
        }
    }

    const QString recursive = findLocalLrcRecursive(dir, m_artist, m_title);
    if (!recursive.isEmpty()) {
        QFile f(recursive);
        if (f.open(QIODevice::ReadOnly)) {
            const QString text = QString::fromUtf8(f.readAll());
            const auto lines = parseLrc(text);
            if (!lines.isEmpty()) {
                setLines(lines, LyricsBackend::Local);
                appendCandidates(
                    { LyricCandidate(LyricsBackend::Local, recursive, m_title, m_artist, m_album, m_duration) });
                m_selected = LyricCandidate(LyricsBackend::Local, recursive, m_title, m_artist, m_album, m_duration);
                emit selectedCandidateChanged();
                if (!m_settingFromPrefs) {
                    persistTrackPrefs();
                }
                setLoading(false);
                return;
            }
        }
    }

    qCDebug(lcLyrics) << "no local lrc for" << m_artist << "-" << m_title;
    chainNext(LyricsBackend::Local, reqId);
}

void Lyrics::tryLrclib(int reqId) {
    if (reqId != m_currentRequestId) {
        return;
    }

    setBackend(LyricsBackend::LRCLIB);

    QUrl url(u"https://lrclib.net/api/get"_s);
    QUrlQuery q;
    q.addQueryItem(u"track_name"_s, m_title);
    q.addQueryItem(u"artist_name"_s, m_artist);
    if (!m_album.isEmpty()) {
        q.addQueryItem(u"album_name"_s, m_album);
    }

    constexpr qreal kMaxDurationSecs = std::numeric_limits<int>::max();
    if (m_duration > 0 && qIsFinite(m_duration) && m_duration < kMaxDurationSecs) {
        q.addQueryItem(u"duration"_s, QString::number(qRound(m_duration)));
    }
    url.setQuery(q);

    auto* reply = getJson(url, lrclibHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "lrclib /get error:" << reply->errorString();
            chainNext(LyricsBackend::LRCLIB, reqId);
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonObject obj = doc.object();
        const QString synced = obj.value(u"syncedLyrics"_s).toString();
        const qint64 id = static_cast<qint64>(obj.value(u"id"_s).toDouble());

        if (synced.isEmpty()) {
            qCDebug(lcLyrics) << "lrclib: no syncedLyrics for" << m_artist << "-" << m_title;
            chainNext(LyricsBackend::LRCLIB, reqId);
            return;
        }

        const auto lines = parseLrc(synced);
        if (lines.isEmpty()) {
            chainNext(LyricsBackend::LRCLIB, reqId);
            return;
        }

        writeCachedLrc(LyricsBackend::LRCLIB, QString::number(id), synced);
        setLines(lines, LyricsBackend::LRCLIB);
        const LyricCandidate cand(LyricsBackend::LRCLIB, QString::number(id), obj.value(u"trackName"_s).toString(),
            obj.value(u"artistName"_s).toString(), obj.value(u"albumName"_s).toString(),
            obj.value(u"duration"_s).toDouble());
        appendCandidates({ cand });
        m_selected = cand;
        emit selectedCandidateChanged();
        if (!m_settingFromPrefs) {
            persistTrackPrefs();
        }
        setLoading(false);
    });
}

void Lyrics::tryNetEase(int reqId) {
    if (reqId != m_currentRequestId) {
        return;
    }

    setBackend(LyricsBackend::NetEase);

    // Reset cookies (LyricsBackend::NetEase rejects requests with stale cookies sometimes)
    m_nam->setCookieJar(new QNetworkCookieJar(m_nam));

    const bool useApiBase = !netEaseApiBase().isEmpty();
    QUrl url = useApiBase ? netEaseApiUrl(u"search"_s) : QUrl(u"https://music.163.com/api/search/get"_s);
    QUrlQuery q;
    q.addQueryItem(useApiBase ? u"keywords"_s : u"s"_s, u"%1 %2"_s.arg(m_title, m_artist));
    q.addQueryItem(u"type"_s, u"1"_s);
    q.addQueryItem(u"limit"_s, u"5"_s);
    url.setQuery(q);

    auto* reply = getJson(url, netEaseHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "netease /search error:" << reply->errorString();
            chainNext(LyricsBackend::NetEase, reqId);
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonArray songs = doc.object().value(u"result"_s).toObject().value(u"songs"_s).toArray();

        // Find best match by artist substring
        LyricCandidate bestCandidate;
        for (const auto& v : songs) {
            const QJsonObject s = v.toObject();
            const QStringList artists = netEaseArtistNames(s);
            if (artists.isEmpty()) {
                continue;
            }
            const QString sArtist = artists.first();
            if (containsCi(m_artist, sArtist) || containsCi(sArtist, m_artist)) {
                bestCandidate = LyricCandidate(LyricsBackend::NetEase,
                    QString::number(static_cast<qint64>(s.value(u"id"_s).toDouble())), s.value(u"name"_s).toString(),
                    artists.join(u", "_s), netEaseAlbumName(s), netEaseDurationSeconds(s));
                break;
            }
        }

        if (!bestCandidate.isValid()) {
            qCDebug(lcLyrics) << "netease: no artist match for" << m_artist << "-" << m_title;
            chainNext(LyricsBackend::NetEase, reqId);
            return;
        }

        fetchNetEaseLyricsById(bestCandidate.id(), reqId, bestCandidate);
    });
}

void Lyrics::tryDeezer(int reqId) {
    if (reqId != m_currentRequestId) {
        return;
    }

    setBackend(LyricsBackend::Deezer);

    if (deezerArl().isEmpty()) {
        qCDebug(lcLyrics) << "deezer: missing ARL";
        chainNext(LyricsBackend::Deezer, reqId);
        return;
    }

    QUrl url(u"https://api.deezer.com/search"_s);
    QUrlQuery q;
    q.addQueryItem(u"q"_s, u"%1 %2"_s.arg(m_title, m_artist));
    q.addQueryItem(u"limit"_s, u"5"_s);
    url.setQuery(q);

    auto* reply = getJson(url, browserHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "deezer /search error:" << reply->errorString();
            chainNext(LyricsBackend::Deezer, reqId);
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonArray tracks = doc.object().value(u"data"_s).toArray();

        LyricCandidate bestCandidate;
        for (const auto& value : tracks) {
            const QJsonObject track = value.toObject();
            const QString artist = deezerArtistName(track);
            if (!artistMatches(m_artist, artist)) {
                continue;
            }
            bestCandidate = LyricCandidate(LyricsBackend::Deezer,
                QString::number(static_cast<qint64>(track.value(u"id"_s).toDouble())),
                track.value(u"title"_s).toString(), artist, deezerAlbumName(track), deezerDurationSeconds(track));
            break;
        }

        if (!bestCandidate.isValid()) {
            qCDebug(lcLyrics) << "deezer: no artist match for" << m_artist << "-" << m_title;
            chainNext(LyricsBackend::Deezer, reqId);
            return;
        }

        fetchDeezerLyricsById(bestCandidate.id(), reqId, bestCandidate, true);
    });
}

void Lyrics::tryMusixmatch(int reqId) {
    if (reqId != m_currentRequestId) {
        return;
    }

    setBackend(LyricsBackend::Musixmatch);

    ensureMusixmatchDesktopToken(reqId, [this, reqId](const QString& token) {
        if (reqId != m_currentRequestId) {
            return;
        }
        if (token.isEmpty()) {
            chainNext(LyricsBackend::Musixmatch, reqId);
            return;
        }

        const QUrl url = musixmatchDesktopUrl(u"track.search"_s, token,
            {
                { u"q_track"_s, m_title },
                { u"q_artist"_s, primaryArtist(m_artist) },
                { u"page_size"_s, u"15"_s },
                { u"page"_s, u"1"_s },
                { u"s_track_rating"_s, u"desc"_s },
            });

        auto* reply = getJson(url, browserHeaders());
        trackReply(reqId, reply);

        QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
            reply->deleteLater();
            if (reqId != m_currentRequestId) {
                return;
            }
            if (reply->error() != QNetworkReply::NoError) {
                qCDebug(lcLyrics) << "musixmatch /track.search error:" << reply->errorString();
                chainNext(LyricsBackend::Musixmatch, reqId);
                return;
            }

            const auto hits = parseMusixmatchCandidates(QJsonDocument::fromJson(reply->readAll()));
            const LyricCandidate bestCandidate = pickBestCandidate(hits, m_title, m_artist, m_duration);
            if (!bestCandidate.isValid()) {
                qCDebug(lcLyrics) << "musixmatch: no match for" << m_artist << "-" << m_title;
                chainNext(LyricsBackend::Musixmatch, reqId);
                return;
            }

            fetchMusixmatchLyricsById(bestCandidate.id(), reqId, bestCandidate, true);
        });
    });
}

void Lyrics::trySpicyLyrics(int reqId) {
    if (reqId != m_currentRequestId) {
        return;
    }

    setBackend(LyricsBackend::SpicyLyrics);

    ensureSpotifyAccessToken(reqId, [this, reqId](const QString& token) {
        if (reqId != m_currentRequestId) {
            return;
        }
        if (token.isEmpty()) {
            qCDebug(lcLyrics) << "spicy lyrics: missing Spotify credentials";
            chainNext(LyricsBackend::SpicyLyrics, reqId);
            return;
        }

        QUrl url(u"https://api.spotify.com/v1/search"_s);
        QUrlQuery q;
        q.addQueryItem(u"type"_s, u"track"_s);
        q.addQueryItem(u"limit"_s, u"5"_s);
        q.addQueryItem(u"q"_s, u"%1 %2"_s.arg(m_title, primaryArtist(m_artist)).trimmed());
        url.setQuery(q);

        auto* reply = getJson(url, bearerHeaders(token));
        trackReply(reqId, reply);

        QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
            reply->deleteLater();
            if (reqId != m_currentRequestId) {
                return;
            }
            if (reply->error() != QNetworkReply::NoError) {
                qCDebug(lcLyrics) << "spotify /search error:" << reply->errorString();
                chainNext(LyricsBackend::SpicyLyrics, reqId);
                return;
            }

            const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
            const QJsonArray tracks =
                doc.object().value(u"tracks"_s).toObject().value(u"items"_s).toArray();

            QList<LyricCandidate> hits;
            hits.reserve(tracks.size());
            for (const auto& value : tracks) {
                const QJsonObject track = value.toObject();
                const QStringList artists = spotifyArtistNames(track);
                hits.append(LyricCandidate(LyricsBackend::SpicyLyrics, track.value(u"id"_s).toString(),
                    track.value(u"name"_s).toString(), artists.join(u", "_s), spotifyAlbumName(track),
                    spotifyDurationSeconds(track)));
            }

            const LyricCandidate bestCandidate = pickBestCandidate(hits, m_title, m_artist, m_duration);
            if (!bestCandidate.isValid()) {
                qCDebug(lcLyrics) << "spicy lyrics: no Spotify track match for" << m_artist << "-" << m_title;
                chainNext(LyricsBackend::SpicyLyrics, reqId);
                return;
            }

            fetchSpicyLyricsById(bestCandidate.id(), reqId, bestCandidate, true);
        });
    });
}

void Lyrics::searchLrclibCandidates(int reqId) {
    QUrl url(u"https://lrclib.net/api/search"_s);
    QUrlQuery q;
    q.addQueryItem(u"track_name"_s, m_title);
    q.addQueryItem(u"artist_name"_s, m_artist);
    url.setQuery(q);

    auto* reply = getJson(url, lrclibHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "lrclib /search error:" << reply->errorString();
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonArray arr = doc.array();

        QList<LyricCandidate> add;
        add.reserve(arr.size());
        for (const auto& v : arr) {
            const QJsonObject o = v.toObject();
            if (o.value(u"syncedLyrics"_s).isNull() && o.value(u"plainLyrics"_s).isNull()) {
                continue;
            }
            add.append(
                LyricCandidate(LyricsBackend::LRCLIB, QString::number(static_cast<qint64>(o.value(u"id"_s).toDouble())),
                    o.value(u"trackName"_s).toString(), o.value(u"artistName"_s).toString(),
                    o.value(u"albumName"_s).toString(), o.value(u"duration"_s).toDouble()));
        }
        appendCandidates(add);
    });
}

void Lyrics::searchNetEaseCandidates(int reqId) {
    m_nam->setCookieJar(new QNetworkCookieJar(m_nam));

    const bool useApiBase = !netEaseApiBase().isEmpty();
    QUrl url = useApiBase ? netEaseApiUrl(u"search"_s) : QUrl(u"https://music.163.com/api/search/get"_s);
    QUrlQuery q;
    q.addQueryItem(useApiBase ? u"keywords"_s : u"s"_s, u"%1 %2"_s.arg(m_title, m_artist));
    q.addQueryItem(u"type"_s, u"1"_s);
    q.addQueryItem(u"limit"_s, u"5"_s);
    url.setQuery(q);

    auto* reply = getJson(url, netEaseHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "netease candidates error:" << reply->errorString();
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonArray songs = doc.object().value(u"result"_s).toObject().value(u"songs"_s).toArray();

        QList<LyricCandidate> add;
        add.reserve(songs.size());
        for (const auto& v : songs) {
            const QJsonObject s = v.toObject();
            const QStringList artistNames = netEaseArtistNames(s);
            add.append(LyricCandidate(LyricsBackend::NetEase,
                QString::number(static_cast<qint64>(s.value(u"id"_s).toDouble())), s.value(u"name"_s).toString(),
                artistNames.join(u", "_s), netEaseAlbumName(s), netEaseDurationSeconds(s)));
        }
        appendCandidates(add);
    });
}

void Lyrics::searchDeezerCandidates(int reqId) {
    if (deezerArl().isEmpty()) {
        return;
    }

    QUrl url(u"https://api.deezer.com/search"_s);
    QUrlQuery q;
    q.addQueryItem(u"q"_s, u"%1 %2"_s.arg(m_title, m_artist));
    q.addQueryItem(u"limit"_s, u"5"_s);
    url.setQuery(q);

    auto* reply = getJson(url, browserHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "deezer candidates error:" << reply->errorString();
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonArray tracks = doc.object().value(u"data"_s).toArray();

        QList<LyricCandidate> add;
        add.reserve(tracks.size());
        for (const auto& value : tracks) {
            const QJsonObject track = value.toObject();
            add.append(LyricCandidate(LyricsBackend::Deezer,
                QString::number(static_cast<qint64>(track.value(u"id"_s).toDouble())),
                track.value(u"title"_s).toString(), deezerArtistName(track), deezerAlbumName(track),
                deezerDurationSeconds(track)));
        }
        appendCandidates(add);
    });
}

void Lyrics::searchMusixmatchCandidates(int reqId) {
    ensureMusixmatchDesktopToken(reqId, [this, reqId](const QString& token) {
        if (reqId != m_currentRequestId) {
            return;
        }
        if (token.isEmpty()) {
            return;
        }

        const QUrl url = musixmatchDesktopUrl(u"track.search"_s, token,
            {
                { u"q_track"_s, m_title },
                { u"q_artist"_s, primaryArtist(m_artist) },
                { u"page_size"_s, u"15"_s },
                { u"page"_s, u"1"_s },
                { u"s_track_rating"_s, u"desc"_s },
            });

        auto* reply = getJson(url, browserHeaders());
        trackReply(reqId, reply);

        QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
            reply->deleteLater();
            if (reqId != m_currentRequestId) {
                return;
            }
            if (reply->error() != QNetworkReply::NoError) {
                qCDebug(lcLyrics) << "musixmatch candidates error:" << reply->errorString();
                return;
            }

            appendCandidates(parseMusixmatchCandidates(QJsonDocument::fromJson(reply->readAll())));
        });
    });
}

void Lyrics::searchSpicyLyricsCandidates(int reqId) {
    ensureSpotifyAccessToken(reqId, [this, reqId](const QString& token) {
        if (reqId != m_currentRequestId) {
            return;
        }
        if (token.isEmpty()) {
            return;
        }

        QUrl url(u"https://api.spotify.com/v1/search"_s);
        QUrlQuery q;
        q.addQueryItem(u"type"_s, u"track"_s);
        q.addQueryItem(u"limit"_s, u"5"_s);
        q.addQueryItem(u"q"_s, u"%1 %2"_s.arg(m_title, primaryArtist(m_artist)).trimmed());
        url.setQuery(q);

        auto* reply = getJson(url, bearerHeaders(token));
        trackReply(reqId, reply);

        QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
            reply->deleteLater();
            if (reqId != m_currentRequestId) {
                return;
            }
            if (reply->error() != QNetworkReply::NoError) {
                qCDebug(lcLyrics) << "spotify candidates error:" << reply->errorString();
                return;
            }

            const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
            const QJsonArray tracks =
                doc.object().value(u"tracks"_s).toObject().value(u"items"_s).toArray();

            QList<LyricCandidate> add;
            add.reserve(tracks.size());
            for (const auto& value : tracks) {
                const QJsonObject track = value.toObject();
                const QStringList artists = spotifyArtistNames(track);
                add.append(LyricCandidate(LyricsBackend::SpicyLyrics, track.value(u"id"_s).toString(),
                    track.value(u"name"_s).toString(), artists.join(u", "_s), spotifyAlbumName(track),
                    spotifyDurationSeconds(track)));
            }
            appendCandidates(add);
        });
    });
}

void Lyrics::fetchLrclibById(const QString& id, int reqId) {
    QUrl url(u"https://lrclib.net/api/get/"_s + id);
    auto* reply = getJson(url, lrclibHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId, id] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(lcLyrics) << "lrclib /get/{id} error:" << reply->errorString();
            setLoading(false);
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QString synced = doc.object().value(u"syncedLyrics"_s).toString();
        if (synced.isEmpty()) {
            qCDebug(lcLyrics) << "lrclib /get/{id}: no syncedLyrics";
            setLoading(false);
            return;
        }
        writeCachedLrc(LyricsBackend::LRCLIB, id, synced);
        setLines(parseLrc(synced), LyricsBackend::LRCLIB);
        setLoading(false);
    });
}

void Lyrics::fetchNetEaseLyricsById(const QString& id, int reqId, const LyricCandidate& candidate) {
    QUrl url = netEaseApiBase().isEmpty() ? QUrl(u"https://music.163.com/api/song/lyric"_s) : netEaseApiUrl(u"lyric"_s);
    QUrlQuery q;
    q.addQueryItem(u"id"_s, id);
    q.addQueryItem(u"lv"_s, u"1"_s);
    q.addQueryItem(u"kv"_s, u"1"_s);
    q.addQueryItem(u"tv"_s, u"-1"_s);
    url.setQuery(q);

    auto* reply = getJson(url, netEaseHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId, id, candidate] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(lcLyrics) << "netease /lyric error:" << reply->errorString();
            setLoading(false);
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QString lrc = doc.object().value(u"lrc"_s).toObject().value(u"lyric"_s).toString();
        if (lrc.isEmpty()) {
            qCDebug(lcLyrics) << "netease /lyric: empty for id" << id;
            setLoading(false);
            return;
        }
        writeCachedLrc(LyricsBackend::NetEase, id, lrc);
        setLines(parseLrc(lrc), LyricsBackend::NetEase);
        if (candidate.isValid()) {
            appendCandidates({ candidate });
            m_selected = candidate;
            emit selectedCandidateChanged();
            if (!m_settingFromPrefs) {
                persistTrackPrefs();
            }
        }
        setLoading(false);
    });
}

void Lyrics::fetchDeezerLyricsById(
    const QString& id, int reqId, const LyricCandidate& candidate, bool chainOnFailure) {
    const QString arl = deezerArl();
    if (arl.isEmpty()) {
        finishProviderFailure(LyricsBackend::Deezer, reqId, chainOnFailure);
        return;
    }

    QUrl url(u"https://auth.deezer.com/login/arl"_s);
    QUrlQuery q;
    q.addQueryItem(u"jo"_s, u"p"_s);
    q.addQueryItem(u"rto"_s, u"c"_s);
    q.addQueryItem(u"i"_s, u"c"_s);
    url.setQuery(q);

    QNetworkRequest req(url);
    req.setRawHeader("Accept"_ba, "application/json"_ba);
    req.setRawHeader("User-Agent"_ba, browserHeaders().value("User-Agent"_ba));
    req.setRawHeader("Cookie"_ba, "arl="_ba + arl.toUtf8());

    auto* reply = m_nam->post(req, QByteArray());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId, id, candidate, chainOnFailure] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(lcLyrics) << "deezer auth error:" << reply->errorString();
            finishProviderFailure(LyricsBackend::Deezer, reqId, chainOnFailure);
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QString jwt = doc.object().value(u"jwt"_s).toString();
        if (jwt.isEmpty()) {
            qCDebug(lcLyrics) << "deezer auth: missing jwt";
            finishProviderFailure(LyricsBackend::Deezer, reqId, chainOnFailure);
            return;
        }

        static const QString query = QStringLiteral(R"(query GetLyrics($trackId: String!) {
  track(trackId: $trackId) {
    lyrics {
      text
      synchronizedLines {
        lrcTimestamp
        line
        milliseconds
      }
      synchronizedWordByWordLines {
        start
        words {
          word
        }
      }
    }
  }
})");

        QJsonObject variables;
        variables.insert(u"trackId"_s, id);

        QJsonObject payload;
        payload.insert(u"operationName"_s, u"GetLyrics"_s);
        payload.insert(u"variables"_s, variables);
        payload.insert(u"query"_s, query);

        auto headers = bearerHeaders(jwt);
        headers.insert("Cookie"_ba, "arl="_ba + deezerArl().toUtf8());

        auto* lyricsReply = postJson(QUrl(u"https://pipe.deezer.com/api"_s), payload, headers);
        trackReply(reqId, lyricsReply);

        QObject::connect(
            lyricsReply, &QNetworkReply::finished, this, [this, lyricsReply, reqId, id, candidate, chainOnFailure] {
                lyricsReply->deleteLater();
                if (reqId != m_currentRequestId) {
                    return;
                }
                if (lyricsReply->error() != QNetworkReply::NoError) {
                    qCWarning(lcLyrics) << "deezer lyrics error:" << lyricsReply->errorString();
                    finishProviderFailure(LyricsBackend::Deezer, reqId, chainOnFailure);
                    return;
                }

                const QJsonDocument lyricsDoc = QJsonDocument::fromJson(lyricsReply->readAll());
                const QJsonObject lyrics = lyricsDoc.object()
                                             .value(u"data"_s)
                                             .toObject()
                                             .value(u"track"_s)
                                             .toObject()
                                             .value(u"lyrics"_s)
                                             .toObject();
                QVector<LyricLine> lines = parseDeezerLines(lyrics.value(u"synchronizedLines"_s).toArray());
                if (lines.isEmpty()) {
                    const QJsonArray wordLines = lyrics.value(u"synchronizedWordByWordLines"_s).toArray();
                    lines.reserve(wordLines.size());
                    for (const auto& value : wordLines) {
                        const QJsonObject line = value.toObject();
                        const QJsonArray words = line.value(u"words"_s).toArray();
                        QStringList parts;
                        parts.reserve(words.size());
                        for (const auto& word : words) {
                            const QString text = word.toObject().value(u"word"_s).toString().trimmed();
                            if (!text.isEmpty()) {
                                parts.append(text);
                            }
                        }
                        const QString text = parts.join(QLatin1Char(' ')).trimmed();
                        if (!text.isEmpty()) {
                            lines.append(LyricLine{ line.value(u"start"_s).toDouble() / 1000.0, text });
                        }
                    }
                }

                if (lines.isEmpty()) {
                    qCDebug(lcLyrics) << "deezer lyrics: no synced lines for id" << id;
                    finishProviderFailure(LyricsBackend::Deezer, reqId, chainOnFailure);
                    return;
                }

                const QString lrc = linesToLrc(lines);
                writeCachedLrc(LyricsBackend::Deezer, id, lrc);
                setLines(lines, LyricsBackend::Deezer);
                if (candidate.isValid()) {
                    appendCandidates({ candidate });
                    m_selected = candidate;
                    emit selectedCandidateChanged();
                    if (!m_settingFromPrefs) {
                        persistTrackPrefs();
                    }
                }
                setLoading(false);
            });
    });
}

void Lyrics::fetchMusixmatchLyricsById(
    const QString& id, int reqId, const LyricCandidate& candidate, bool chainOnFailure) {
    ensureMusixmatchDesktopToken(reqId, [this, id, reqId, candidate, chainOnFailure](const QString& token) {
        if (reqId != m_currentRequestId) {
            return;
        }
        if (token.isEmpty()) {
            finishProviderFailure(LyricsBackend::Musixmatch, reqId, chainOnFailure);
            return;
        }

        QList<QPair<QString, QString>> pairs = {
            { u"track_id"_s, id },
            { u"subtitle_format"_s, u"lrc"_s },
        };
        const int seconds = qRound(candidate.duration());
        if (seconds > 0) {
            pairs.append({ u"f_subtitle_length"_s, QString::number(std::max(1, seconds)) });
            pairs.append({ u"f_subtitle_length_max_deviation"_s, u"8"_s });
        }

        auto* reply = getJson(musixmatchDesktopUrl(u"track.subtitle.get"_s, token, pairs), browserHeaders());
        trackReply(reqId, reply);

        QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId, id, candidate, chainOnFailure] {
            reply->deleteLater();
            if (reqId != m_currentRequestId) {
                return;
            }
            if (reply->error() != QNetworkReply::NoError) {
                qCWarning(lcLyrics) << "musixmatch /track.subtitle.get error:" << reply->errorString();
                finishProviderFailure(LyricsBackend::Musixmatch, reqId, chainOnFailure);
                return;
            }

            const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
            const QJsonObject message = doc.object().value(u"message"_s).toObject();
            const int status = message.value(u"header"_s).toObject().value(u"status_code"_s).toInt(-1);
            const QString lrc = message.value(u"body"_s)
                                    .toObject()
                                    .value(u"subtitle"_s)
                                    .toObject()
                                    .value(u"subtitle_body"_s)
                                    .toString()
                                    .trimmed();
            const auto lines = parseLrc(lrc);
            if (status != 200 || lines.isEmpty() || lrc == u"***"_s || lrc.startsWith(u"*******"_s)) {
                qCDebug(lcLyrics) << "musixmatch subtitle: empty for id" << id;
                finishProviderFailure(LyricsBackend::Musixmatch, reqId, chainOnFailure);
                return;
            }

            writeCachedLrc(LyricsBackend::Musixmatch, id, lrc);
            setLines(lines, LyricsBackend::Musixmatch);
            if (candidate.isValid()) {
                appendCandidates({ candidate });
                m_selected = candidate;
                emit selectedCandidateChanged();
                if (!m_settingFromPrefs) {
                    persistTrackPrefs();
                }
            }
            setLoading(false);
        });
    });
}

void Lyrics::fetchSpicyLyricsById(
    const QString& id, int reqId, const LyricCandidate& candidate, bool chainOnFailure) {
    ensureSpotifyAccessToken(reqId, [this, id, reqId, candidate, chainOnFailure](const QString& token) {
        if (reqId != m_currentRequestId) {
            return;
        }
        if (token.isEmpty()) {
            finishProviderFailure(LyricsBackend::SpicyLyrics, reqId, chainOnFailure);
            return;
        }

        QJsonObject variables;
        variables.insert(u"id"_s, id);
        variables.insert(u"auth"_s, u"SpicyLyrics-WebAuth"_s);

        QJsonObject query;
        query.insert(u"operation"_s, u"lyrics"_s);
        query.insert(u"variables"_s, variables);

        QJsonObject client;
        client.insert(u"version"_s, u"6.1.1"_s);

        QJsonObject payload;
        payload.insert(u"queries"_s, QJsonArray{ query });
        payload.insert(u"client"_s, client);

        QHash<QByteArray, QByteArray> headers;
        headers.insert("SpicyLyrics-WebAuth"_ba, "Bearer "_ba + token.toUtf8());
        headers.insert("SpicyLyrics-Version"_ba, "6.1.1"_ba);

        auto* reply = postJson(QUrl(u"https://api.spicylyrics.org/query"_s), payload, headers);
        trackReply(reqId, reply);

        QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId, id, candidate, chainOnFailure] {
            reply->deleteLater();
            if (reqId != m_currentRequestId) {
                return;
            }
            if (reply->error() != QNetworkReply::NoError) {
                qCWarning(lcLyrics) << "spicy lyrics /query error:" << reply->errorString();
                finishProviderFailure(LyricsBackend::SpicyLyrics, reqId, chainOnFailure);
                return;
            }

            const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
            const QJsonArray queries = doc.object().value(u"queries"_s).toArray();
            if (queries.isEmpty()) {
                qCDebug(lcLyrics) << "spicy lyrics: missing query result";
                finishProviderFailure(LyricsBackend::SpicyLyrics, reqId, chainOnFailure);
                return;
            }

            const QJsonObject result = queries.first().toObject().value(u"result"_s).toObject();
            const int httpStatus = result.value(u"httpStatus"_s).toInt();
            if (httpStatus != 200) {
                qCDebug(lcLyrics) << "spicy lyrics: status" << httpStatus << "for id" << id;
                finishProviderFailure(LyricsBackend::SpicyLyrics, reqId, chainOnFailure);
                return;
            }

            const QJsonValue unpacked = unpackSpicyPayload(result.value(u"data"_s));
            const QVector<LyricLine> lines = parseSpicyLyricsObject(unpacked.toObject());
            if (lines.isEmpty()) {
                qCDebug(lcLyrics) << "spicy lyrics: no synced lines for id" << id;
                finishProviderFailure(LyricsBackend::SpicyLyrics, reqId, chainOnFailure);
                return;
            }

            const QString lrc = linesToLrc(lines);
            writeCachedLrc(LyricsBackend::SpicyLyrics, id, lrc);
            setLines(lines, LyricsBackend::SpicyLyrics);
            if (candidate.isValid()) {
                appendCandidates({ candidate });
                m_selected = candidate;
                emit selectedCandidateChanged();
                if (!m_settingFromPrefs) {
                    persistTrackPrefs();
                }
            }
            setLoading(false);
        });
    });
}

QNetworkReply* Lyrics::getJson(const QUrl& url, const QHash<QByteArray, QByteArray>& headers) {
    QNetworkRequest req(url);
    req.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    req.setRawHeader("Cache-Control"_ba, "no-cache, no-store"_ba);
    req.setRawHeader("Pragma"_ba, "no-cache"_ba);
    req.setRawHeader("Connection"_ba, "close"_ba);
    req.setRawHeader("Accept"_ba, "application/json"_ba);
    for (auto it = headers.constBegin(); it != headers.constEnd(); ++it) {
        req.setRawHeader(it.key(), it.value());
    }
    return m_nam->get(req);
}

QNetworkReply* Lyrics::postJson(
    const QUrl& url, const QJsonObject& payload, const QHash<QByteArray, QByteArray>& headers) {
    QNetworkRequest req(url);
    req.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    req.setHeader(QNetworkRequest::ContentTypeHeader, u"application/json"_s);
    req.setRawHeader("Cache-Control"_ba, "no-cache, no-store"_ba);
    req.setRawHeader("Pragma"_ba, "no-cache"_ba);
    req.setRawHeader("Connection"_ba, "close"_ba);
    req.setRawHeader("Accept"_ba, "application/json"_ba);
    for (auto it = headers.constBegin(); it != headers.constEnd(); ++it) {
        req.setRawHeader(it.key(), it.value());
    }
    return m_nam->post(req, QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

void Lyrics::finishProviderFailure(LyricsBackend::Backend backend, int reqId, bool chainOnFailure) {
    if (reqId != m_currentRequestId) {
        return;
    }
    if (chainOnFailure) {
        chainNext(backend, reqId);
        return;
    }
    setLoading(false);
}

void Lyrics::onPreferredBackendConfigChanged() {
    auto* svcCfg = config::GlobalConfig::instance()->services();
    const LyricsBackend::Backend desired = backendFromKey(svcCfg->lyricsBackend());
    if (desired == m_preferredBackend) {
        return;
    }
    m_preferredBackend = desired;
    emit preferredBackendChanged();
    scheduleLoad();
}

void Lyrics::onProviderConfigChanged() {
    m_spotifyAccessTokenCache.clear();
    m_spotifyAccessTokenExpiresAtMs = 0;
    scheduleLoad();
}

void Lyrics::onLyricsDirChanged() {
    scheduleLoad();
}

void Lyrics::loadLyricsMap() {
    m_lyricsMap = {};
    m_lyricsMapLoaded = false;

    QFile f(lyricsMapPath());
    if (!f.open(QIODevice::ReadOnly)) {
        m_lyricsMapLoaded = true;
        return;
    }
    const QByteArray bytes = f.readAll();
    f.close();

    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(bytes, &err);
    if (err.error != QJsonParseError::NoError) {
        qCWarning(lcLyrics) << "lyrics_map.json parse error:" << err.errorString();
        m_lyricsMapLoaded = true;
        return;
    }
    m_lyricsMap = doc.object();
    m_lyricsMapLoaded = true;
}

void Lyrics::persistTrackPrefs() {
    if (!m_lyricsMapLoaded || trackKey().isEmpty()) {
        return;
    }
    const QString key = trackKey();
    QJsonObject entry = m_lyricsMap.value(key).toObject();
    entry.insert(u"offset"_s, m_offset);
    if (m_selected.isValid()) {
        entry.insert(u"backend"_s, backendKey(m_selected.backend()));
        entry.insert(u"id"_s, m_selected.id());
    }
    m_lyricsMap.insert(key, entry);

    QDir().mkpath(stateDir());

    QSaveFile out(lyricsMapPath());
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qCWarning(lcLyrics) << "cannot open" << lyricsMapPath() << "for write:" << out.errorString();
        return;
    }
    const QByteArray bytes = QJsonDocument(m_lyricsMap).toJson(QJsonDocument::Compact);
    if (out.write(bytes) != bytes.size()) {
        qCWarning(lcLyrics) << "short write to" << lyricsMapPath();
        out.cancelWriting();
        return;
    }
    if (!out.commit()) {
        qCWarning(lcLyrics) << "commit failed for" << lyricsMapPath() << ":" << out.errorString();
    }
}

QString Lyrics::lyricsDir() const {
    QString dir = config::GlobalConfig::instance()->paths()->lyricsDir();
    if (dir.isEmpty()) {
        return {};
    }
    if (dir == u"~"_s) {
        dir = QDir::homePath();
    } else if (dir.startsWith(u"~/"_s)) {
        dir.replace(0, 1, QDir::homePath());
    }
    while (dir.endsWith(QLatin1Char('/')) && dir.size() > 1) {
        dir.chop(1);
    }
    return dir;
}

QString Lyrics::netEaseApiBase() const {
    QString base = config::GlobalConfig::instance()->services()->lyricsNetEaseApiBase().trimmed();
    while (base.endsWith(QLatin1Char('/'))) {
        base.chop(1);
    }
    return base;
}

QString Lyrics::deezerArl() const {
    return config::GlobalConfig::instance()->services()->lyricsDeezerArl().trimmed();
}

QString Lyrics::spotifyAccessToken() const {
    QString token = config::GlobalConfig::instance()->services()->lyricsSpotifyAccessToken().trimmed();
    if (token.startsWith(u"Bearer "_s, Qt::CaseInsensitive)) {
        token.remove(0, 7);
        token = token.trimmed();
    }
    return token;
}

QUrl Lyrics::netEaseApiUrl(const QString& endpoint) const {
    QString base = netEaseApiBase();
    if (base.isEmpty()) {
        return {};
    }
    QString path = endpoint;
    while (path.startsWith(QLatin1Char('/'))) {
        path.remove(0, 1);
    }
    return QUrl(base + QLatin1Char('/') + path);
}

QUrl Lyrics::musixmatchDesktopUrl(
    const QString& endpoint, const QString& userToken, const QList<QPair<QString, QString>>& extraParams,
    const QString& signKey) {
    if (m_musixmatchDesktopGuid.isEmpty()) {
        m_musixmatchDesktopGuid = QUuid::createUuid().toString(QUuid::WithoutBraces);
    }

    QList<QPair<QString, QString>> pairs = extraParams;
    pairs.append({ u"format"_s, u"json"_s });
    pairs.append({ u"app_id"_s, kMusixmatchDesktopAppId });
    if (!userToken.isEmpty()) {
        pairs.append({ u"usertoken"_s, userToken });
    }
    pairs.append({ u"guid"_s, m_musixmatchDesktopGuid });

    const QString unsignedUrl = kMusixmatchDesktopApiRoot + endpoint + QLatin1Char('?') + buildQuery(pairs);
    const QString day = QDate::currentDate().toString(u"yyyyMMdd"_s);
    const QString key = signKey.isEmpty() ? m_musixmatchSignKey : signKey;
    const QString signature = hmacSha1Base64(unsignedUrl + day, key.isEmpty() ? kMusixmatchFallbackSignKey : key);
    return QUrl(unsignedUrl + u"&signature="_s + percentEncode(signature) + u"&signature_protocol=sha1"_s);
}

void Lyrics::ensureMusixmatchDesktopToken(int reqId, std::function<void(const QString&)> callback) {
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (!m_musixmatchDesktopUserToken.isEmpty() && now < m_musixmatchDesktopTokenExpiresAtMs) {
        callback(m_musixmatchDesktopUserToken);
        return;
    }

    ensureMusixmatchSignKey(reqId, [this, reqId, callback = std::move(callback)](const QString& signKey) {
        auto* reply = getJson(musixmatchDesktopUrl(u"token.get"_s, QString(), {}, signKey), browserHeaders());
        trackReply(reqId, reply);

        QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId, callback] {
            reply->deleteLater();
            if (reqId != m_currentRequestId) {
                return;
            }
            if (reply->error() != QNetworkReply::NoError) {
                qCDebug(lcLyrics) << "musixmatch token error:" << reply->errorString();
                callback(QString());
                return;
            }

            const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
            const QJsonObject message = doc.object().value(u"message"_s).toObject();
            const int status = message.value(u"header"_s).toObject().value(u"status_code"_s).toInt(-1);
            const QString token = message.value(u"body"_s).toObject().value(u"user_token"_s).toString().trimmed();
            if (status != 200 || token.isEmpty()) {
                callback(QString());
                return;
            }

            m_musixmatchDesktopUserToken = token;
            m_musixmatchDesktopTokenExpiresAtMs =
                QDateTime::currentMSecsSinceEpoch() + kMusixmatchDesktopTokenTtlMs;
            callback(token);
        });
    });
}

void Lyrics::ensureMusixmatchSignKey(int reqId, std::function<void(const QString&)> callback) {
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (!m_musixmatchSignKey.isEmpty() && now < m_musixmatchSignKeyExpiresAtMs) {
        callback(m_musixmatchSignKey);
        return;
    }

    auto finish = [this, reqId, callback = std::move(callback)](const QString& signKey) {
        if (reqId != m_currentRequestId) {
            return;
        }
        m_musixmatchSignKey = signKey.isEmpty() ? kMusixmatchFallbackSignKey : signKey;
        m_musixmatchSignKeyExpiresAtMs = QDateTime::currentMSecsSinceEpoch() + kMusixmatchSignKeyTtlMs;
        callback(m_musixmatchSignKey);
    };

    auto* reply = getJson(QUrl(u"https://www.musixmatch.com/community"_s), browserHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId, finish] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "musixmatch community error:" << reply->errorString();
            finish(kMusixmatchFallbackSignKey);
            return;
        }

        const QString scriptUrl = musixmatchScriptUrlFromCommunityPage(QString::fromUtf8(reply->readAll()));
        if (scriptUrl.isEmpty()) {
            finish(kMusixmatchFallbackSignKey);
            return;
        }

        auto* scriptReply = getJson(QUrl(scriptUrl), browserHeaders());
        trackReply(reqId, scriptReply);

        QObject::connect(scriptReply, &QNetworkReply::finished, this, [this, scriptReply, reqId, finish] {
            scriptReply->deleteLater();
            if (reqId != m_currentRequestId) {
                return;
            }
            if (scriptReply->error() != QNetworkReply::NoError) {
                qCDebug(lcLyrics) << "musixmatch script error:" << scriptReply->errorString();
                finish(kMusixmatchFallbackSignKey);
                return;
            }

            static const QRegularExpression signKeyRegex(u"signatureSecret\\s*:\\s*[\"'](.{40})[\"']"_s);
            const auto match = signKeyRegex.match(QString::fromUtf8(scriptReply->readAll()));
            finish(match.hasMatch() ? match.captured(1) : kMusixmatchFallbackSignKey);
        });
    });
}

void Lyrics::ensureSpotifyAccessToken(int reqId, std::function<void(const QString&)> callback) {
    const QString direct = spotifyAccessToken();
    if (!direct.isEmpty()) {
        callback(direct);
        return;
    }

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (!m_spotifyAccessTokenCache.isEmpty() && now < m_spotifyAccessTokenExpiresAtMs - 120000) {
        callback(m_spotifyAccessTokenCache);
        return;
    }

    auto* const svcCfg = config::GlobalConfig::instance()->services();
    const QString clientId = svcCfg->lyricsSpotifyClientId().trimmed();
    const QString clientSecret = svcCfg->lyricsSpotifyClientSecret().trimmed();
    if (clientId.isEmpty() || clientSecret.isEmpty()) {
        callback(QString());
        return;
    }

    QNetworkRequest req(QUrl(u"https://accounts.spotify.com/api/token"_s));
    req.setRawHeader("Accept"_ba, "application/json"_ba);
    req.setRawHeader("Content-Type"_ba, "application/x-www-form-urlencoded"_ba);
    req.setRawHeader("Authorization"_ba, "Basic "_ba + (clientId + QLatin1Char(':') + clientSecret).toUtf8().toBase64());

    auto* reply = m_nam->post(req, "grant_type=client_credentials"_ba);
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId, callback = std::move(callback)] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "spotify token error:" << reply->errorString();
            callback(QString());
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QString token = doc.object().value(u"access_token"_s).toString().trimmed();
        if (token.isEmpty()) {
            callback(QString());
            return;
        }

        const int expiresIn = doc.object().value(u"expires_in"_s).toInt(3500);
        m_spotifyAccessTokenCache = token;
        m_spotifyAccessTokenExpiresAtMs = QDateTime::currentMSecsSinceEpoch() + qMax(60, expiresIn) * 1000;
        callback(token);
    });
}

QString Lyrics::lyricsMapPath() const {
    return stateDir() + u"/lyrics_map.json"_s;
}

QString Lyrics::trackKey() const {
    if (m_artist.isEmpty() && m_title.isEmpty()) {
        return {};
    }
    return u"%1 - %2"_s.arg(joinArtists(m_artist), m_title);
}

QString Lyrics::backendKey(LyricsBackend::Backend value) {
    switch (value) {
    case LyricsBackend::Local:
        return u"Local"_s;
    case LyricsBackend::LRCLIB:
        return u"LRCLIB"_s;
    case LyricsBackend::NetEase:
        return u"NetEase"_s;
    case LyricsBackend::Deezer:
        return u"Deezer"_s;
    case LyricsBackend::Musixmatch:
        return u"Musixmatch"_s;
    case LyricsBackend::SpicyLyrics:
        return u"SpicyLyrics"_s;
    case LyricsBackend::Auto:
    default:
        return u"Auto"_s;
    }
}

LyricsBackend::Backend Lyrics::backendFromKey(const QString& key) {
    if (key.compare(u"Local"_s, Qt::CaseInsensitive) == 0) {
        return LyricsBackend::Local;
    }
    if (key.compare(u"LRCLIB"_s, Qt::CaseInsensitive) == 0) {
        return LyricsBackend::LRCLIB;
    }
    if (key.compare(u"NetEase"_s, Qt::CaseInsensitive) == 0) {
        return LyricsBackend::NetEase;
    }
    if (key.compare(u"NetEaseV2"_s, Qt::CaseInsensitive) == 0) {
        return LyricsBackend::NetEase;
    }
    if (key.compare(u"Deezer"_s, Qt::CaseInsensitive) == 0) {
        return LyricsBackend::Deezer;
    }
    if (key.compare(u"Musixmatch"_s, Qt::CaseInsensitive) == 0) {
        return LyricsBackend::Musixmatch;
    }
    if (key.compare(u"SpicyLyrics"_s, Qt::CaseInsensitive) == 0) {
        return LyricsBackend::SpicyLyrics;
    }
    return LyricsBackend::Auto;
}

const QString& Lyrics::stateDir() {
    static const QString s_dir = [] {
        QString state = qEnvironmentVariable("XDG_STATE_HOME");
        if (state.isEmpty()) {
            state = QDir::homePath() + u"/.local/state"_s;
        }
        return state + u"/caelestia/lyrics"_s;
    }();
    return s_dir;
}

const QString& Lyrics::cacheDir() {
    static const QString s_dir = [] {
        QString cache = qEnvironmentVariable("XDG_CACHE_HOME");
        if (cache.isEmpty()) {
            cache = QDir::homePath() + u"/.cache"_s;
        }
        return cache + u"/caelestia/lyrics"_s;
    }();
    return s_dir;
}

QString Lyrics::cachePathFor(LyricsBackend::Backend backend, const QString& id) {
    if (id.isEmpty() || backend == LyricsBackend::Auto || backend == LyricsBackend::Local) {
        return {};
    }
    return u"%1/%2/%3.lrc"_s.arg(cacheDir(), backendKey(backend), sanitizeFilenamePart(id));
}

QString Lyrics::readCachedLrc(LyricsBackend::Backend backend, const QString& id) {
    const QString path = cachePathFor(backend, id);
    if (path.isEmpty()) {
        return {};
    }
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromUtf8(f.readAll());
}

void Lyrics::writeCachedLrc(LyricsBackend::Backend backend, const QString& id, const QString& text) {
    if (text.isEmpty()) {
        return;
    }
    const QString path = cachePathFor(backend, id);
    if (path.isEmpty()) {
        return;
    }
    QDir().mkpath(QFileInfo(path).absolutePath());

    QSaveFile out(path);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qCWarning(lcLyrics) << "cannot open" << path << "for write:" << out.errorString();
        return;
    }
    const QByteArray bytes = text.toUtf8();
    if (out.write(bytes) != bytes.size()) {
        qCWarning(lcLyrics) << "short write to" << path;
        out.cancelWriting();
        return;
    }
    if (!out.commit()) {
        qCWarning(lcLyrics) << "commit failed for" << path << ":" << out.errorString();
    }
}

QString Lyrics::tryReadLocalLrc(const QString& dir, const QString& artist, const QString& title) {
    if (artist.isEmpty() && title.isEmpty()) {
        return {};
    }
    const QString flat = u"%1/%2 - %3.lrc"_s.arg(dir, sanitizeFilenamePart(artist), sanitizeFilenamePart(title));
    return QFile::exists(flat) ? flat : QString();
}

QString Lyrics::findLocalLrcRecursive(const QString& dir, const QString& artist, const QString& title) {
    if (dir.isEmpty()) {
        return {};
    }
    if (artist.isEmpty() && title.isEmpty()) {
        return {};
    }

    QDirIterator it(dir, QStringList{ u"*.lrc"_s }, QDir::Files | QDir::NoDotAndDotDot,
        QDirIterator::Subdirectories | QDirIterator::FollowSymlinks);

    while (it.hasNext()) {
        const QString path = it.next();
        const QString name = it.fileName();
        if ((artist.isEmpty() || containsCi(name, artist)) && (title.isEmpty() || containsCi(name, title))) {
            return path;
        }
    }
    return {};
}

QVector<LyricLine> Lyrics::parseLrc(const QString& text) {
    QVector<LyricLine> result;
    if (text.isEmpty()) {
        return result;
    }

    static const QRegularExpression timeRegex(u"\\[(\\d+):(\\d+(?:\\.\\d+)?)\\]"_s);
    static const QStringList creditKeywords = {
        u"作词"_s,
        u"作曲"_s,
        u"编曲"_s,
        u"制作"_s,
        u"收录"_s,
        u"演奏"_s,
        u"词："_s,
        u"曲："_s,
        u"Lyricist"_s,
        u"Composer"_s,
        u"Arranger"_s,
        u"Producer"_s,
        u"Mixing"_s,
        u"Mastering"_s,
    };

    const QStringList lines = text.split(QLatin1Char('\n'));
    for (const QString& line : lines) {
        QList<QRegularExpressionMatch> matches;
        auto it = timeRegex.globalMatch(line);
        while (it.hasNext()) {
            matches.append(it.next());
        }
        if (matches.isEmpty()) {
            continue;
        }

        QString lyric = line;
        lyric.replace(timeRegex, QString());
        lyric = lyric.trimmed();

        const qreal firstTime = matches.first().captured(1).toInt() * 60.0 + matches.first().captured(2).toDouble();

        if (firstTime < 20.0) {
            bool isCredit = false;
            for (const QString& k : creditKeywords) {
                if (lyric.contains(k, Qt::CaseInsensitive)) {
                    isCredit = true;
                    break;
                }
            }
            if (isCredit && (lyric.contains(QLatin1Char(':')) || lyric.contains(QChar(0xFF1A)) || lyric.size() < 25)) {
                continue;
            }
        }

        for (const auto& m : matches) {
            const qreal t = m.captured(1).toInt() * 60.0 + m.captured(2).toDouble();
            result.append(LyricLine{ t, lyric });
        }
    }

    std::sort(result.begin(), result.end(), [](const LyricLine& a, const LyricLine& b) {
        return a.time < b.time;
    });

    return result;
}

} // namespace caelestia::services
