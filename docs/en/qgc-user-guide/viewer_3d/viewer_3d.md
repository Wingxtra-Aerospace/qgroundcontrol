# 3D View

The 3D View is used to visualize and monitor the vehicle, the environment, and the planned mission in 3D. Most of the capabilities available in the [Fly View](../fly_view/fly_view.md)  is also available in the 3D View. 

You can use it to:
- Stream online 3D terrain + imagery for the current fly area.
- Display the vehicle along with its mission in 3D.
- And most of the capabilities of the [Fly View](../fly_view/fly_view.md), including:
    - Run an automated [pre-flight checklist](#preflight_checklist).
    - Arm the vehicle (or check why it won't arm).
    - Control missions: [start](#start_mission), [continue](#continue_mission), [pause](#pause), and [resume](#resume_mission).
    - Guide the vehicle to [arm](#arm)/[disarm](#disarm)/[emergency stop](#emergency_stop), [takeoff](#takeoff)/[land](#land), [change altitude](#change_altitude), and [return/RTL](#rtl).
    - Switch between a map view and a video view (if available)
    - Display video, mission, telemetry, and other information for the current vehicle, and also switch between connected vehicles.

![3D View](../../../assets/viewer_3d/viewer_3d_overview.jpg)

# UI Overview
The screenshot above shows the main elements of the 3D View. 

<font color="red">**Enabling the 3D View:** </font>The 3D View is disabled by default. To enable it, go to **Application Settings** ->**Fly View** tab, and under the **3D View** settings group, toggle the **Enabled** switch as shown below:

![3D View](../../../assets/viewer_3d/enable_3d_view.jpg)

To open the 3D View, when you are in the [Fly View](../fly_view/fly_view.md), from the toolbar on the left, select the 3D View icon as illustrated below:

![3D View](../../../assets/viewer_3d/open_3d_viewer.jpg)

Once the 3D View is opened, you can navigate through the 3D environment by using either a mouse or a touchscreen as follows:
- **Mouse:**
    - **To move horizontally and vertically**: Press and hold the mouse left-click, then move the cursor.
    - **To rotate**: Press and hold the mouse right-click, then move the cursor.
    - **To zoom**: Use the mouse wheel\middle button.

- **Touchscreen:**
    - **To move horizontally and vertically**: Use a single finger, then tap and move your finger.
    - **To rotate**: Use two fingers, then tap and move your fingers while keeping them together.
    - **To zoom**: Use a pinch with two fingers and move them together or apart to zoom in or out.

The streamed 3D viewer requires internet access and a valid Mapbox access token configured in **Application Settings** -> **Fly View** -> **3D View**.
# Settings
You can change the settings of the 3D View from **Application Settings** ->**Fly View** tab under the **3D View** settings group.
The following properties can be modified in the 3D View settings group:

- **Enabled**: To enable or disable the 3D View.
- **Mapbox Access Token**: Token used by the streamed 3D provider to load terrain and imagery.
- **Vehicle Altitude Bias**: Altitude correction bias (in meters) applied to vehicle and mission 3D overlays when the flight controller altitude estimate is offset from rendered terrain.

