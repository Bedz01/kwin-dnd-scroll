# SPDX-FileCopyrightText: 2026 Bedz01
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.16)
project(kwin-dnd-scroll LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM 6.0.0 REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)

# KWin::kwin links Qt6::DBus/Widgets/Quick but its config does not find them.
find_package(Qt6 REQUIRED COMPONENTS Core Gui DBus Widgets Quick)
find_package(KF6CoreAddons REQUIRED)
find_package(KWin REQUIRED)

kcoreaddons_add_plugin(dndscroll
    SOURCES src/dndscroll.cpp
    INSTALL_NAMESPACE "kwin/plugins"
)
target_link_libraries(dndscroll PRIVATE KWin::kwin Qt6::Core Qt6::Gui)
