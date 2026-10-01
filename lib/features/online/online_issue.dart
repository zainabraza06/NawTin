import '../../services/online/online_service.dart';

/// The designed full-screen states of online play. Each has one message and one
/// action; none of them blames the player or shows a code.
enum OnlineIssue { notConfigured, outdated, replaced, signInFailed, noInternet, serverDown }

enum IssueAction { back, update, useHere, retry }

class IssueCopy {
  const IssueCopy(this.title, this.message, this.actionLabel, this.action);
  final String title;
  final String message;
  final String actionLabel;
  final IssueAction action;
}

const issueCopy = <OnlineIssue, IssueCopy>{
  OnlineIssue.notConfigured: IssueCopy(
    'Online play is not available',
    'This version of Naw Tin cannot reach the online server. You can still play against the AI or a friend on this phone.',
    'Back to home',
    IssueAction.back,
  ),
  OnlineIssue.outdated: IssueCopy(
    'Please update the app',
    'A newer version of Naw Tin is needed to play online. Update it from the store and come back.',
    'Update',
    IssueAction.update,
  ),
  OnlineIssue.replaced: IssueCopy(
    'Naw Tin is open somewhere else',
    'Your game is open on another screen. Only one can be connected at a time.',
    'Use it here',
    IssueAction.useHere,
  ),
  OnlineIssue.signInFailed: IssueCopy(
    "Couldn't sign you in",
    "We couldn't set up your online player. Check your connection and try again.",
    'Try again',
    IssueAction.retry,
  ),
  OnlineIssue.noInternet: IssueCopy(
    'No internet connection',
    'Connect to Wi-Fi or mobile data to play online.',
    'Try again',
    IssueAction.retry,
  ),
  OnlineIssue.serverDown: IssueCopy(
    "Can't reach the game server",
    "Your internet works, but the game server isn't answering. It may be restarting. We keep trying.",
    'Try now',
    IssueAction.retry,
  ),
};

/// Which full-screen state (if any) the connection is in.
///
/// Brief hiccups are not issues: the first failed attempts just look like
/// "connecting". After [patience] failed attempts the screen explains what is
/// wrong, telling a missing network apart from a server that is down.
OnlineIssue? issueFor(ConnectionState c, {required bool hasNetwork, int patience = 2}) {
  switch (c.stopReason) {
    case StopReason.notConfigured:
      return OnlineIssue.notConfigured;
    case StopReason.outdated:
      return OnlineIssue.outdated;
    case StopReason.replaced:
      return OnlineIssue.replaced;
    case StopReason.unauthorized:
    case StopReason.authUnavailable:
      return OnlineIssue.signInFailed;
    case null:
      break;
  }
  final trying = c.phase == ConnPhase.connecting || c.phase == ConnPhase.reconnecting;
  if (trying && c.attempt >= patience) {
    if (!hasNetwork) return OnlineIssue.noInternet;
    if (c.problem == Problem.unreachable || c.problem == Problem.handshakeTimeout || c.problem == Problem.dropped) {
      return OnlineIssue.serverDown;
    }
  }
  if (!hasNetwork && (trying || c.phase == ConnPhase.idle) && c.attempt >= 1) return OnlineIssue.noInternet;
  return null;
}
