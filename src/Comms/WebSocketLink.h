/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#pragma once

#include <QtCore/QByteArray>
#include <QtCore/QList>
#include <QtCore/QLoggingCategory>
#include <QtCore/QString>
#include <QtNetwork/QAbstractSocket>
#include <QtNetwork/QHostAddress>

#include "LinkConfiguration.h"
#include "LinkInterface.h"

class QThread;
class QUdpSocket;
class QWebSocket;
class QWebSocketServer;

Q_DECLARE_LOGGING_CATEGORY(WebSocketLinkLog)

/*===========================================================================*/

class WebSocketConfiguration : public LinkConfiguration
{
    Q_OBJECT

    Q_PROPERTY(QString listenAddress READ listenAddress WRITE setListenAddress NOTIFY listenAddressChanged)
    Q_PROPERTY(quint16 listenPort READ listenPort WRITE setListenPort NOTIFY listenPortChanged)
    Q_PROPERTY(bool secureMode READ secureMode WRITE setSecureMode NOTIFY secureModeChanged)
    Q_PROPERTY(QString certificatePath READ certificatePath WRITE setCertificatePath NOTIFY certificatePathChanged)
    Q_PROPERTY(QString privateKeyPath READ privateKeyPath WRITE setPrivateKeyPath NOTIFY privateKeyPathChanged)
    Q_PROPERTY(bool udpForwardingEnabled READ udpForwardingEnabled WRITE setUdpForwardingEnabled NOTIFY udpForwardingEnabledChanged)
    Q_PROPERTY(QString udpForwardHost READ udpForwardHost WRITE setUdpForwardHost NOTIFY udpForwardHostChanged)
    Q_PROPERTY(quint16 udpForwardPort READ udpForwardPort WRITE setUdpForwardPort NOTIFY udpForwardPortChanged)

public:
    explicit WebSocketConfiguration(const QString &name, QObject *parent = nullptr);
    explicit WebSocketConfiguration(const WebSocketConfiguration *copy, QObject *parent = nullptr);
    ~WebSocketConfiguration() override;

    LinkType type() const override { return LinkConfiguration::TypeWebSocket; }
    void copyFrom(const LinkConfiguration *source) override;
    void loadSettings(QSettings &settings, const QString &root) override;
    void saveSettings(QSettings &settings, const QString &root) const override;
    QString settingsURL() const override { return QStringLiteral("WebSocketSettings.qml"); }
    QString settingsTitle() const override { return tr("WebSocket Link Settings"); }

    QString listenAddress() const { return _listenAddress; }
    quint16 listenPort() const { return _listenPort; }
    bool secureMode() const { return _secureMode; }
    QString certificatePath() const { return _certificatePath; }
    QString privateKeyPath() const { return _privateKeyPath; }
    bool udpForwardingEnabled() const { return _udpForwardingEnabled; }
    QString udpForwardHost() const { return _udpForwardHost; }
    quint16 udpForwardPort() const { return _udpForwardPort; }

    void setListenAddress(const QString &address);
    void setListenPort(quint16 port);
    void setSecureMode(bool secure);
    void setCertificatePath(const QString &path);
    void setPrivateKeyPath(const QString &path);
    void setUdpForwardingEnabled(bool enabled);
    void setUdpForwardHost(const QString &host);
    void setUdpForwardPort(quint16 port);

signals:
    void listenAddressChanged();
    void listenPortChanged();
    void secureModeChanged();
    void certificatePathChanged();
    void privateKeyPathChanged();
    void udpForwardingEnabledChanged();
    void udpForwardHostChanged();
    void udpForwardPortChanged();

private:
    QString _listenAddress;
    quint16 _listenPort = 8812;
    bool _secureMode = false;
    QString _certificatePath;
    QString _privateKeyPath;
    bool _udpForwardingEnabled = false;
    QString _udpForwardHost;
    quint16 _udpForwardPort = 14550;
};

/*===========================================================================*/

class WebSocketWorker : public QObject
{
    Q_OBJECT

public:
    explicit WebSocketWorker(const WebSocketConfiguration *config, QObject *parent = nullptr);
    ~WebSocketWorker() override;

    bool isConnected() const;

signals:
    void connected();
    void disconnected();
    void errorOccurred(const QString &errorString);
    void dataReceived(const QByteArray &data);
    void dataSent(const QByteArray &data);

public slots:
    void setupServer();
    void startServer();
    void stopServer();
    void writeData(const QByteArray &data);

private slots:
    void _onNewConnection();
    void _onSocketDisconnected();
    void _onBinaryMessageReceived(const QByteArray &message);
    void _onTextMessageReceived(const QString &message);
    void _onSocketErrorOccurred(QAbstractSocket::SocketError socketError);

private:
    QHostAddress _resolveAddress(const QString &host) const;
    bool _loadTlsConfiguration();
    void _forwardToUdp(const QByteArray &data);

    const WebSocketConfiguration *_wsConfig = nullptr;
    QWebSocketServer *_server = nullptr;
    QList<QWebSocket *> _clients;
    QUdpSocket *_udpForwardSocket = nullptr;
    bool _isConnected = false;
};

/*===========================================================================*/

class WebSocketLink : public LinkInterface
{
    Q_OBJECT

public:
    explicit WebSocketLink(SharedLinkConfigurationPtr &config, QObject *parent = nullptr);
    ~WebSocketLink() override;

    bool isConnected() const override;
    void disconnect() override;
    bool isSecureConnection() const override;

private slots:
    void _writeBytes(const QByteArray &bytes) override;
    void _onConnected();
    void _onDisconnected();
    void _onErrorOccurred(const QString &errorString);
    void _onDataReceived(const QByteArray &data);
    void _onDataSent(const QByteArray &data);

private:
    bool _connect() override;

    const WebSocketConfiguration *_wsConfig = nullptr;
    WebSocketWorker *_worker = nullptr;
    QThread *_workerThread = nullptr;
};

