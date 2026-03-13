/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "WebSocketLink.h"
#include "QGCLoggingCategory.h"

#include <QtCore/QFile>
#include <QtCore/QThread>
#include <QtCore/QUrl>
#include <QtNetwork/QHostInfo>
#include <QtNetwork/QSslCertificate>
#include <QtNetwork/QSslConfiguration>
#include <QtNetwork/QSslKey>
#include <QtNetwork/QSslSocket>
#include <QtNetwork/QUdpSocket>
#include <QtWebSockets/QWebSocket>
#include <QtWebSockets/QWebSocketServer>

QGC_LOGGING_CATEGORY(WebSocketLinkLog, "qgc.comms.websocketlink")

namespace {

QString normalizeLocalPath(const QString &path)
{
    if (path.isEmpty()) {
        return path;
    }

    const QUrl maybeUrl(path);
    if (maybeUrl.isLocalFile()) {
        return maybeUrl.toLocalFile();
    }

    return path;
}

bool isLocalOnlyListenAddress(const QString &host)
{
    const QString normalized = host.trimmed().toLower();
    return normalized.isEmpty()
        || (normalized == QStringLiteral("localhost"))
        || (normalized == QStringLiteral("127.0.0.1"))
        || (normalized == QStringLiteral("::1"))
        || (normalized == QStringLiteral("[::1]"));
}

} // namespace

/*===========================================================================*/

WebSocketConfiguration::WebSocketConfiguration(const QString &name, QObject *parent)
    : LinkConfiguration(name, parent)
    , _listenAddress(QStringLiteral("127.0.0.1"))
    , _udpForwardHost(QStringLiteral("127.0.0.1"))
{
}

WebSocketConfiguration::WebSocketConfiguration(const WebSocketConfiguration *copy, QObject *parent)
    : LinkConfiguration(copy, parent)
{
    WebSocketConfiguration::copyFrom(copy);
}

WebSocketConfiguration::~WebSocketConfiguration() = default;

void WebSocketConfiguration::copyFrom(const LinkConfiguration *source)
{
    Q_ASSERT(source);
    LinkConfiguration::copyFrom(source);

    const WebSocketConfiguration *const wsSource = qobject_cast<const WebSocketConfiguration *>(source);
    Q_ASSERT(wsSource);

    setListenAddress(wsSource->listenAddress());
    setListenPort(wsSource->listenPort());
    setSecureMode(wsSource->secureMode());
    setCertificatePath(wsSource->certificatePath());
    setPrivateKeyPath(wsSource->privateKeyPath());
    setUdpForwardingEnabled(wsSource->udpForwardingEnabled());
    setUdpForwardHost(wsSource->udpForwardHost());
    setUdpForwardPort(wsSource->udpForwardPort());
}

void WebSocketConfiguration::loadSettings(QSettings &settings, const QString &root)
{
    settings.beginGroup(root);

    setListenAddress(settings.value(QStringLiteral("listenAddress"), _listenAddress).toString());
    setListenPort(static_cast<quint16>(settings.value(QStringLiteral("listenPort"), _listenPort).toUInt()));
    setSecureMode(settings.value(QStringLiteral("secureMode"), _secureMode).toBool());
    setCertificatePath(settings.value(QStringLiteral("certificatePath"), _certificatePath).toString());
    setPrivateKeyPath(settings.value(QStringLiteral("privateKeyPath"), _privateKeyPath).toString());
    setUdpForwardingEnabled(settings.value(QStringLiteral("udpForwardingEnabled"), _udpForwardingEnabled).toBool());
    setUdpForwardHost(settings.value(QStringLiteral("udpForwardHost"), _udpForwardHost).toString());
    setUdpForwardPort(static_cast<quint16>(settings.value(QStringLiteral("udpForwardPort"), _udpForwardPort).toUInt()));

    settings.endGroup();
}

void WebSocketConfiguration::saveSettings(QSettings &settings, const QString &root) const
{
    settings.beginGroup(root);

    settings.setValue(QStringLiteral("listenAddress"), _listenAddress);
    settings.setValue(QStringLiteral("listenPort"), _listenPort);
    settings.setValue(QStringLiteral("secureMode"), _secureMode);
    settings.setValue(QStringLiteral("certificatePath"), _certificatePath);
    settings.setValue(QStringLiteral("privateKeyPath"), _privateKeyPath);
    settings.setValue(QStringLiteral("udpForwardingEnabled"), _udpForwardingEnabled);
    settings.setValue(QStringLiteral("udpForwardHost"), _udpForwardHost);
    settings.setValue(QStringLiteral("udpForwardPort"), _udpForwardPort);

    settings.endGroup();
}

void WebSocketConfiguration::setListenAddress(const QString &address)
{
    if (address != _listenAddress) {
        _listenAddress = address;
        emit listenAddressChanged();
    }
}

void WebSocketConfiguration::setListenPort(quint16 port)
{
    if (port != _listenPort) {
        _listenPort = port;
        emit listenPortChanged();
    }
}

void WebSocketConfiguration::setSecureMode(bool secure)
{
    if (secure != _secureMode) {
        _secureMode = secure;
        emit secureModeChanged();
    }
}

void WebSocketConfiguration::setCertificatePath(const QString &path)
{
    if (path != _certificatePath) {
        _certificatePath = path;
        emit certificatePathChanged();
    }
}

void WebSocketConfiguration::setPrivateKeyPath(const QString &path)
{
    if (path != _privateKeyPath) {
        _privateKeyPath = path;
        emit privateKeyPathChanged();
    }
}

void WebSocketConfiguration::setUdpForwardingEnabled(bool enabled)
{
    if (enabled != _udpForwardingEnabled) {
        _udpForwardingEnabled = enabled;
        emit udpForwardingEnabledChanged();
    }
}

void WebSocketConfiguration::setUdpForwardHost(const QString &host)
{
    if (host != _udpForwardHost) {
        _udpForwardHost = host;
        emit udpForwardHostChanged();
    }
}

void WebSocketConfiguration::setUdpForwardPort(quint16 port)
{
    if (port != _udpForwardPort) {
        _udpForwardPort = port;
        emit udpForwardPortChanged();
    }
}

/*===========================================================================*/

WebSocketWorker::WebSocketWorker(const WebSocketConfiguration *config, QObject *parent)
    : QObject(parent)
    , _wsConfig(config)
{
}

WebSocketWorker::~WebSocketWorker()
{
    stopServer();
}

bool WebSocketWorker::isConnected() const
{
    return _isConnected;
}

void WebSocketWorker::setupServer()
{
    if (_server) {
        return;
    }

    const QWebSocketServer::SslMode sslMode = _wsConfig->secureMode()
        ? QWebSocketServer::SecureMode
        : QWebSocketServer::NonSecureMode;
    _server = new QWebSocketServer(_wsConfig->name(), sslMode, this);

    (void) connect(_server, &QWebSocketServer::newConnection, this, &WebSocketWorker::_onNewConnection);
}

void WebSocketWorker::startServer()
{
    if (!_server) {
        setupServer();
    }

    if (_isConnected || !_server) {
        return;
    }

    if (_wsConfig->secureMode() && !_loadTlsConfiguration()) {
        return;
    }

    if (!isLocalOnlyListenAddress(_wsConfig->listenAddress())) {
        emit errorOccurred(tr("Only localhost listen addresses are allowed in this build (%1).")
                               .arg(_wsConfig->listenAddress()));
        return;
    }

    const QHostAddress listenAddress = _resolveAddress(_wsConfig->listenAddress());
    if (listenAddress.isNull()) {
        emit errorOccurred(tr("Invalid listen address: %1").arg(_wsConfig->listenAddress()));
        return;
    }

    if (!_server->listen(listenAddress, _wsConfig->listenPort())) {
        emit errorOccurred(tr("Failed to listen on %1:%2 (%3)")
                               .arg(listenAddress.toString())
                               .arg(_wsConfig->listenPort())
                               .arg(_server->errorString()));
        return;
    }

    if (!_udpForwardSocket) {
        _udpForwardSocket = new QUdpSocket(this);
    }

    qCDebug(WebSocketLinkLog) << "WebSocket server listening on"
                              << (_wsConfig->secureMode() ? "wss://" : "ws://")
                              << listenAddress.toString() << _wsConfig->listenPort();

    _isConnected = true;
    emit connected();
}

void WebSocketWorker::stopServer()
{
    for (QWebSocket *socket : std::as_const(_clients)) {
        if (!socket) {
            continue;
        }
        (void) disconnect(socket, nullptr, this, nullptr);
        socket->close();
        socket->deleteLater();
    }
    _clients.clear();

    if (_server && _server->isListening()) {
        _server->close();
    }

    if (_udpForwardSocket) {
        _udpForwardSocket->close();
    }

    if (_isConnected) {
        _isConnected = false;
        emit disconnected();
    }
}

void WebSocketWorker::writeData(const QByteArray &data)
{
    if (!_isConnected || data.isEmpty()) {
        return;
    }

    QList<QWebSocket *> staleSockets;
    for (QWebSocket *socket : std::as_const(_clients)) {
        if (!socket || socket->state() != QAbstractSocket::ConnectedState) {
            staleSockets.append(socket);
            continue;
        }
        socket->sendBinaryMessage(data);
    }

    for (QWebSocket *staleSocket : staleSockets) {
        _clients.removeAll(staleSocket);
        if (staleSocket) {
            staleSocket->deleteLater();
        }
    }

    emit dataSent(data);
}

void WebSocketWorker::_onNewConnection()
{
    while (_server && _server->hasPendingConnections()) {
        QWebSocket *const socket = _server->nextPendingConnection();
        if (!socket) {
            continue;
        }

        (void) connect(socket, &QWebSocket::binaryMessageReceived, this, &WebSocketWorker::_onBinaryMessageReceived);
        (void) connect(socket, &QWebSocket::textMessageReceived, this, &WebSocketWorker::_onTextMessageReceived);
        (void) connect(socket, &QWebSocket::disconnected, this, &WebSocketWorker::_onSocketDisconnected);
        (void) connect(socket, qOverload<QAbstractSocket::SocketError>(&QWebSocket::errorOccurred), this, &WebSocketWorker::_onSocketErrorOccurred);

        _clients.append(socket);
        qCDebug(WebSocketLinkLog) << "WebSocket client connected from" << socket->peerAddress().toString();
    }
}

void WebSocketWorker::_onSocketDisconnected()
{
    QWebSocket *const socket = qobject_cast<QWebSocket *>(sender());
    if (!socket) {
        return;
    }

    qCDebug(WebSocketLinkLog) << "WebSocket client disconnected from" << socket->peerAddress().toString();
    _clients.removeAll(socket);
    socket->deleteLater();
}

void WebSocketWorker::_onBinaryMessageReceived(const QByteArray &message)
{
    if (message.isEmpty()) {
        return;
    }

    emit dataReceived(message);
    _forwardToUdp(message);
}

void WebSocketWorker::_onTextMessageReceived(const QString &message)
{
    if (message.isEmpty()) {
        return;
    }

    const QByteArray utf8 = message.toUtf8();
    emit dataReceived(utf8);
    _forwardToUdp(utf8);
}

void WebSocketWorker::_onSocketErrorOccurred(QAbstractSocket::SocketError socketError)
{
    Q_UNUSED(socketError);
    const QWebSocket *const socket = qobject_cast<QWebSocket *>(sender());
    if (socket) {
        emit errorOccurred(tr("WebSocket client error from %1: %2")
                               .arg(socket->peerAddress().toString())
                               .arg(socket->errorString()));
    } else {
        emit errorOccurred(tr("WebSocket client error"));
    }
}

QHostAddress WebSocketWorker::_resolveAddress(const QString &host) const
{
    const QString trimmed = host.trimmed();
    if (trimmed.isEmpty() || (trimmed.compare(QStringLiteral("localhost"), Qt::CaseInsensitive) == 0)) {
        return QHostAddress(QHostAddress::LocalHost);
    }

    QHostAddress hostAddress;
    if (hostAddress.setAddress(trimmed)) {
        return hostAddress;
    }

    const QHostInfo info = QHostInfo::fromName(trimmed);
    if (info.error() != QHostInfo::NoError) {
        return QHostAddress();
    }

    for (const QHostAddress &address : info.addresses()) {
        if (address.protocol() == QAbstractSocket::IPv4Protocol) {
            return address;
        }
    }

    if (!info.addresses().isEmpty()) {
        return info.addresses().constFirst();
    }

    return QHostAddress();
}

bool WebSocketWorker::_loadTlsConfiguration()
{
    const QString certPath = normalizeLocalPath(_wsConfig->certificatePath().trimmed());
    const QString keyPath = normalizeLocalPath(_wsConfig->privateKeyPath().trimmed());
    if (certPath.isEmpty() || keyPath.isEmpty()) {
        emit errorOccurred(tr("WSS requires certificate and private key paths."));
        return false;
    }

    QFile certFile(certPath);
    if (!certFile.open(QIODevice::ReadOnly)) {
        emit errorOccurred(tr("Cannot open certificate file: %1").arg(certPath));
        return false;
    }
    const QByteArray certData = certFile.readAll();
    certFile.close();

    const QList<QSslCertificate> certificates = QSslCertificate::fromData(certData);
    if (certificates.isEmpty()) {
        emit errorOccurred(tr("Invalid certificate file: %1").arg(certPath));
        return false;
    }

    QFile keyFile(keyPath);
    if (!keyFile.open(QIODevice::ReadOnly)) {
        emit errorOccurred(tr("Cannot open private key file: %1").arg(keyPath));
        return false;
    }
    const QByteArray keyData = keyFile.readAll();
    keyFile.close();

    QSslKey privateKey;
    const QList<QSsl::KeyAlgorithm> algorithms = { QSsl::Rsa, QSsl::Ec, QSsl::Dsa };
    for (const QSsl::KeyAlgorithm algorithm : algorithms) {
        privateKey = QSslKey(keyData, algorithm, QSsl::Pem, QSsl::PrivateKey);
        if (!privateKey.isNull()) {
            break;
        }
        privateKey = QSslKey(keyData, algorithm, QSsl::Der, QSsl::PrivateKey);
        if (!privateKey.isNull()) {
            break;
        }
    }

    if (privateKey.isNull()) {
        emit errorOccurred(tr("Invalid private key file: %1").arg(keyPath));
        return false;
    }

    QSslConfiguration sslConfig = QSslConfiguration::defaultConfiguration();
    sslConfig.setLocalCertificate(certificates.constFirst());
    sslConfig.setPrivateKey(privateKey);
    sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone);
    sslConfig.setProtocol(QSsl::TlsV1_2OrLater);
    _server->setSslConfiguration(sslConfig);

    return true;
}

void WebSocketWorker::_forwardToUdp(const QByteArray &data)
{
    if (!_wsConfig->udpForwardingEnabled() || !_udpForwardSocket || data.isEmpty()) {
        return;
    }

    const quint16 targetPort = _wsConfig->udpForwardPort();
    if (targetPort == 0) {
        return;
    }

    const QHostAddress targetAddress = _resolveAddress(_wsConfig->udpForwardHost());
    if (targetAddress.isNull()) {
        emit errorOccurred(tr("Invalid UDP forward host: %1").arg(_wsConfig->udpForwardHost()));
        return;
    }

    if (_udpForwardSocket->writeDatagram(data, targetAddress, targetPort) < 0) {
        emit errorOccurred(tr("Failed UDP forward to %1:%2 (%3)")
                               .arg(targetAddress.toString())
                               .arg(targetPort)
                               .arg(_udpForwardSocket->errorString()));
    }
}

/*===========================================================================*/

WebSocketLink::WebSocketLink(SharedLinkConfigurationPtr &config, QObject *parent)
    : LinkInterface(config, parent)
    , _wsConfig(qobject_cast<const WebSocketConfiguration *>(config.get()))
    , _worker(new WebSocketWorker(_wsConfig))
    , _workerThread(new QThread(this))
{
    _workerThread->setObjectName(QStringLiteral("WS_%1").arg(_wsConfig->name()));
    _worker->moveToThread(_workerThread);

    (void) connect(_workerThread, &QThread::started, _worker, &WebSocketWorker::setupServer);
    (void) connect(_workerThread, &QThread::finished, _worker, &QObject::deleteLater);

    (void) connect(_worker, &WebSocketWorker::connected, this, &WebSocketLink::_onConnected, Qt::QueuedConnection);
    (void) connect(_worker, &WebSocketWorker::disconnected, this, &WebSocketLink::_onDisconnected, Qt::QueuedConnection);
    (void) connect(_worker, &WebSocketWorker::errorOccurred, this, &WebSocketLink::_onErrorOccurred, Qt::QueuedConnection);
    (void) connect(_worker, &WebSocketWorker::dataReceived, this, &WebSocketLink::_onDataReceived, Qt::QueuedConnection);
    (void) connect(_worker, &WebSocketWorker::dataSent, this, &WebSocketLink::_onDataSent, Qt::QueuedConnection);

    _workerThread->start();
}

WebSocketLink::~WebSocketLink()
{
    WebSocketLink::disconnect();

    _workerThread->quit();
    if (!_workerThread->wait()) {
        qCWarning(WebSocketLinkLog) << "Failed to wait for WebSocket thread to close";
    }
}

bool WebSocketLink::isConnected() const
{
    return _worker->isConnected();
}

bool WebSocketLink::_connect()
{
    return QMetaObject::invokeMethod(_worker, "startServer", Qt::QueuedConnection);
}

void WebSocketLink::disconnect()
{
    (void) QMetaObject::invokeMethod(_worker, "stopServer", Qt::QueuedConnection);
}

bool WebSocketLink::isSecureConnection() const
{
    if (_wsConfig->secureMode()) {
        return true;
    }

    const QString host = _wsConfig->listenAddress().trimmed().toLower();
    return (host == QStringLiteral("localhost")) || (host == QStringLiteral("127.0.0.1")) || (host == QStringLiteral("::1"));
}

void WebSocketLink::_writeBytes(const QByteArray &bytes)
{
    (void) QMetaObject::invokeMethod(_worker, "writeData", Qt::QueuedConnection, Q_ARG(QByteArray, bytes));
}

void WebSocketLink::_onConnected()
{
    emit connected();
}

void WebSocketLink::_onDisconnected()
{
    emit disconnected();
}

void WebSocketLink::_onErrorOccurred(const QString &errorString)
{
    emit communicationError(tr("WebSocket Link Error"),
                            tr("Link %1: (Host: %2 Port: %3) %4")
                                .arg(_wsConfig->name(), _wsConfig->listenAddress())
                                .arg(_wsConfig->listenPort())
                                .arg(errorString));
}

void WebSocketLink::_onDataReceived(const QByteArray &data)
{
    emit bytesReceived(this, data);
}

void WebSocketLink::_onDataSent(const QByteArray &data)
{
    emit bytesSent(this, data);
}
