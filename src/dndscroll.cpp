// SPDX-FileCopyrightText: 2026 Bedz01
// SPDX-License-Identifier: GPL-2.0-or-later
//
// KWin plugin: deliver wheel events to the drop target during a pointer drag.
// Why and how: ../README.md#how-it-works

#include <input.h>
#include <input_event.h>
#include <input_event_spy.h>
#include <keyboard_input.h>
#include <plugin.h>
#include <wayland/display.h>
#include <wayland/pointer.h>
#include <wayland/seat.h>
#include <wayland/surface.h>
#include <wayland_server.h>
#include <window.h>
#include <xkb.h>

#include <QPointer>

namespace KWin
{

class DndScrollFilter;

// InputEventSpy and InputEventFilter clash on pointerAxis/pointerMotion, so the spy is its own object.
class DragMotionSpy : public InputEventSpy
{
public:
    explicit DragMotionSpy(DndScrollFilter *filter)
        : m_filter(filter)
    {
    }

    void pointerMotion(PointerMotionEvent *) override;

private:
    DndScrollFilter *m_filter;
};

class DndScrollFilter : public Plugin, public InputEventFilter
{
    Q_OBJECT

public:
    // Same weight as ForwardInputFilter; lower_bound inserts us just ahead of it,
    // so every other filter (global shortcuts, effects, decorations) still goes first.
    DndScrollFilter()
        : InputEventFilter(InputFilterOrder::Forward)
        , m_spy(this)
    {
        input()->installInputEventFilter(this);
        input()->installInputEventSpy(&m_spy);
        connect(waylandServer()->seat(), &SeatInterface::dragEnded, this, &DndScrollFilter::release);
    }

    ~DndScrollFilter() override
    {
        release();
        input()->uninstallInputEventSpy(&m_spy);
        input()->uninstallInputEventFilter(this);
    }

    bool pointerAxis(PointerAxisEvent *event) override
    {
        SeatInterface *seat = waylandServer()->seat();
        if(!seat->isDragPointer()) return false;
        // Scroll Lock on = off switch: stock behaviour, the seat drops the wheel.
        if(input()->keyboard()->xkb()->leds() & LED::ScrollLock) return false;

        SurfaceInterface *surface = seat->dragSurface();
        PointerInterface *pointer = seat->pointer();
        if(!surface || !pointer) return false;

        // dragSurface() is not updated for Xwayland targets; MUST match the window under the cursor.
        Window *window = input()->findToplevel(event->position);
        if(!window || !window->surface() || window->surface() != surface->mainSurface()) return false;

        // Focus is lent until the drag leaves this surface or ends, not per event: Qt compresses
        // frames <100us apart onto a timer, and a leave in the same burst aborts the scroll.
        const QPointF local = seat->dragSurfaceTransformation().map(event->position);
        seat->setTimestamp(event->timestamp);
        if(pointer->focusedSurface() != surface){
            watch(pointer);
            m_lending = true;
            pointer->sendEnter(surface, local, seat->display()->nextSerial());
            m_lending = false;
            m_lent    = surface;
        } else if(m_lent == surface){
            pointer->sendMotion(local);
        }
        pointer->sendAxis(event->orientation, event->delta, event->deltaV120, event->source, event->inverted);
        pointer->sendFrame();
        return true;
    }

    void dragMoved()
    {
        SeatInterface *seat = waylandServer()->seat();
        if(m_lent && seat->isDragPointer() && seat->dragSurface() != m_lent) release();
    }

private:
    // The seat's own focus is never touched, so the drop's button release still is not sent
    // to the target (seat.cpp notifyPointerButton); KWin re-enters normally after the drag.
    void release()
    {
        if(!m_lent) return;
        PointerInterface *pointer = waylandServer()->seat()->pointer();
        if(pointer && pointer->focusedSurface() == m_lent){
            m_lending = true;
            pointer->sendLeave(waylandServer()->seat()->display()->nextSerial());
            m_lending = false;
        }
        m_lent = nullptr;
    }

    // Anyone else moving pointer focus ends the loan. KWin's own dragEnded handler runs before
    // ours and re-enters the surface; leaving after that would strand the pointer (no focus).
    void watch(PointerInterface *pointer)
    {
        if(m_watched == pointer) return;
        m_watched = pointer;
        connect(pointer, &PointerInterface::focusedSurfaceChanged, this, [this]{
            if(!m_lending) m_lent = nullptr;
        });
    }

    DragMotionSpy              m_spy;
    QPointer<SurfaceInterface> m_lent;
    QPointer<PointerInterface> m_watched;
    bool                       m_lending = false;
};

// Spies run before the filters, so dragSurface() is one motion event behind; good enough.
void DragMotionSpy::pointerMotion(PointerMotionEvent *)
{
    m_filter->dragMoved();
}

class DndScrollFactory : public PluginFactory
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID PluginFactory_iid FILE "metadata.json")
    Q_INTERFACES(KWin::PluginFactory)

public:
    std::unique_ptr<Plugin> create() const override
    {
        return std::make_unique<DndScrollFilter>();
    }
};

} // namespace KWin

#include "dndscroll.moc"
