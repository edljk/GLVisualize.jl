using Gtk, GLWindow, GLAbstraction, Reactive, GeometryTypes, Colors, GLVisualize
using GtkReactive
using Gtk.GConstants, ModernGL


mutable struct GtkContext <: GLWindow.AbstractContext
    window::Gtk.GLArea
    framebuffer::GLWindow.GLFramebuffer
end
function make_context_current(screen::Screen)
    gl_area = screen.glcontext.window
    Gtk.make_current(gl_area)
end
GLWindow.isopen(x::Gtk.GLArea) = true

global screen = Ref{Screen}()
function init_screen(gl_area, resolution, mesh_color)
    Gtk.make_current(gl_area)
    gtk_context = GtkContext(gl_area, GLWindow.GLFramebuffer(Signal(resolution)))
    window_area = Signal(SimpleRectangle(0, 0, resolution...))
    signals = Dict(
        :mouse_button_released => Reactive.Signal(0),
        :mouse_buttons_pressed => Reactive.Signal(Set(Int[])),
        :scroll => Reactive.Signal(Vec(0.0, 0.0)),
        :buttons_pressed => Reactive.Signal(Set(Int[])),
        :window_size => Reactive.Signal(Vec(resolution...)),
        :window_area => window_area,
        :cursor_position => Reactive.Signal(Vec(0.0,0.0)),
        :mouseinside => Reactive.Signal(true),
        :mouse_button_down => Reactive.Signal(0),
        :mouseposition => Reactive.Signal(Vec(0.0, 0.0)),
        :framebuffer_size => Reactive.Signal(Vec(resolution...)),
        :button_down => Reactive.Signal(0),
        :button_released => Reactive.Signal(0),
        :window_open => Reactive.Signal(true),
        :keyboard_buttons => Reactive.Signal((0,0,0,0)),
        :mouse2id => Signal(GLWindow.SelectionID{Int}(-1, -1))
    )
    screen[] = Screen(
        Symbol("GLVisualize"), window_area, nothing,
        Screen[], signals,
        (), false, true, RGBA(1f0,1f0,1f0,1f0), (0f0, RGBA(0f0,0f0,0f0,0f0)),
        Dict{Symbol, Any}(),
        gtk_context
    )

    GLVisualize.add_screen(screen[])
    timesignal = loop(linspace(0f0,1f0,360))
    rotation_angle  = const_lift(*, timesignal, 2f0*pi)
    start_rotation  = Signal(rotationmatrix_x(deg2rad(90f0)))
    rotation        = map(rotationmatrix_y, rotation_angle)
    final_rotation  = map(*, start_rotation, rotation)
    foreach(final_rotation) do x
        # render a frame each time rotation updates
        Gtk.queue_render(gl_area)
        return
    end
    _view(visualize(loadasset("cat.obj"), color = mesh_color, model = final_rotation), screen[])
    # renderloop(screen[])

end

function render_gtk(window, gtk_area)
    !isopen(window) && return
    fb = GLWindow.framebuffer(window)
    wh = GeometryTypes.widths(window)
    resize!(fb, wh)
    w, h = wh
    #prepare for geometry in need of anti aliasing
    glBindFramebuffer(GL_FRAMEBUFFER, fb.id[1]) # color framebuffer
    glDrawBuffers(2, [GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1])
    # setup stencil and backgrounds
    glEnable(GL_STENCIL_TEST)
    glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)
    glStencilMask(0xff)
    glClearStencil(0)
    glClearColor(0,0,0,0)
    glClear(GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT | GL_COLOR_BUFFER_BIT)
    glEnable(GL_SCISSOR_TEST)
    GLWindow.setup_window(window, false)
    glDisable(GL_SCISSOR_TEST)
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)
    # deactivate stencil write
    glEnable(GL_STENCIL_TEST)
    glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)
    glStencilMask(0x00)
    GLAbstraction.render(window, true)
    glDisable(GL_STENCIL_TEST)

    # transfer color to luma buffer and apply fxaa
    glBindFramebuffer(GL_FRAMEBUFFER, fb.id[2]) # luma framebuffer
    glDrawBuffer(GL_COLOR_ATTACHMENT0)
    glClearColor(0,0,0,0)
    glClear(GL_COLOR_BUFFER_BIT)
    glViewport(0, 0, w, h)
    GLAbstraction.render(fb.postprocess[1]) # add luma and preprocess

    glBindFramebuffer(GL_FRAMEBUFFER, fb.id[1]) # transfer to non fxaa framebuffer
    glDrawBuffer(GL_COLOR_ATTACHMENT0)
    GLAbstraction.render(fb.postprocess[2]) # copy with fxaa postprocess

    #prepare for non anti aliased pass
    glDrawBuffers(2, [GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1])

    glEnable(GL_STENCIL_TEST)
    glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)
    glStencilMask(0x00)
    GLAbstraction.render(window, false)
    glDisable(GL_STENCIL_TEST)
    # draw strokes
    glEnable(GL_SCISSOR_TEST)
    GLWindow.setup_window(window, true)
    glDisable(GL_SCISSOR_TEST)
    glViewport(0,0, wh...)
    #Read all the selection queries
    GLWindow.push_selectionqueries!(window)
    Gtk.attach_buffers(gtk_area) # transfer back to window
    glClearColor(0,0,0,0)
    glClear(GL_COLOR_BUFFER_BIT)
    GLAbstraction.render(fb.postprocess[3]) # copy postprocess
    return
end
function connect_renderloop(gl_area, resolution, mesh_color)

end
function setup_screen()
    resolution = (600, 500)
    name = "GTK + GLVisualize"
    parent = Gtk.Window(name, resolution..., true, true)
    Gtk.visible(parent, true)
    Gtk.setproperty!(parent, Symbol("is-focus"), false)
    box = Gtk.Box(:v)
    push!(parent, box)
    sl = GtkReactive.slider(linspace(0.0, 1.0, 100))
    push!(box, sl)
    mesh_color = map(sl) do val
        RGBA{Float32}(val, 0,0,1)
    end
    # mesh_color = Signal(RGBA{Float32}(1,0,0,1))

    gl_area = Gtk.GLArea()
    Gtk.gl_area_set_required_version(gl_area, 3, 3)
    GLAbstraction.new_context()
    push!(box, gl_area)
    Gtk.setproperty!(box, :expand, gl_area, true)
    Gtk.showall(parent)
    Gtk.signal_connect(gl_area, "render") do gl_area, gdk_context
        if !isassigned(screen)
            init_screen(gl_area, resolution, mesh_color)
        end
        render_gtk(screen[], gl_area)
        glFlush()
        return false
    end
    return parent
end


parent = setup_screen();
Gtk.showall(parent)
