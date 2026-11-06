namespace SaySpan.Core;

// Re-arm capture at startup and when either selection setting changes. This is
// independent of mouse events: opening Settings must not be needed to start capture.
public sealed class SelectionSettingsTracker
{
    (bool Enabled, bool Automatic)? previous;
    public bool Update(Preferences preferences)
    {
        var current = (preferences.SelectionEnabled, preferences.AutomaticSelection);
        if (previous == current) return false;
        previous = current;
        return true;
    }
}
