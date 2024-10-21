# Screenshot Macro for MacOS

This repository contains Python scripts that automate the process of taking screenshots, automating keyboard inputs, and converting images into a PDF. **These scripts are only compatible with MacOS**, as they rely on the `screencapture` command-line utility, which is native to Mac systems.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Option 1: Macro Mode](#option-1-macro-mode)
  - [Option 2: View Mode](#option-2-view-mode)
  - [Option 3: Clean Mode](#option-3-clean-mode)
- [Project Structure](#project-structure)
- [Notes](#notes)
- [License](#license)
- [Contact](#contact)

## Features

- **Macro Mode**: Automatically captures screenshots of a specified area multiple times with customizable delays and automates right arrow key presses.
- **View Mode**: Captures a screenshot every time the right arrow key is pressed. Key listening can be started and stopped via the GUI.
- **Clean Mode**: Deletes all screenshots stored in the `screenshots` folder.
- **PDF Conversion**: Combines captured screenshots into a single PDF file.

## Requirements

- **MacOS** (due to the usage of the `screencapture` command)
- **Python 3.6** or higher

To install the required Python libraries, run:

```bash
pip install -r requirements.txt
```

## Installation

### 1. Clone or Download the Repository

```bash
git clone https://github.com/yourusername/ScreenshotMacro.git
cd ScreenshotMacro
```

### 2. (Optional) Create and Activate a Virtual Environment

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

Alternatively, install the package locally:

```bash
pip install -e .
```

## Usage

After installation, you can run the application using the `screenshot-macro` command followed by the desired mode:

```bash
screenshot-macro <mode>
```

Where `<mode>` is one of `macro`, `view`, or `clean`.

### Option 1: Macro Mode

Automates screenshot capturing and keyboard inputs.

```bash
screenshot-macro macro
```

1. **Set the Screenshot Area**:

   - Click **"Set Top-Left"** and select the top-left corner of the area.
   - Click **"Set Bottom-Right"** and select the bottom-right corner.

2. **Configure Settings**:

   - **Repetitions**: Enter the number of screenshots to capture.
   - **Delay (s)**: Enter the delay between each screenshot.
   - **Use Random Delay**: Check this to use a random delay between the specified minimum and maximum values.

3. **Start the Macro**:

   - Click **"Start Macro"** to begin.
   - The macro will capture screenshots and simulate right arrow key presses.

4. **Cancel the Macro**:
   - Click **"Cancel Macro"** to stop the macro at any time.

### Option 2: View Mode

Captures a screenshot each time the right arrow key is pressed.

```bash
screenshot-macro view
```

1. **Set the Screenshot Area**:

   - Click **"Set Top-Left"** and select the top-left corner of the area.
   - Click **"Set Bottom-Right"** and select the bottom-right corner.

2. **Start Key Listener**:

   - Click **"Start Key Listener"** to begin listening for the right arrow key.

3. **Capture Screenshots**:

   - Press the **Right Arrow Key** to capture a screenshot of the specified area.
   - Screenshots are saved in the `screenshots` folder.

4. **Stop Key Listener**:

   - Click **"Stop Key Listener"** to stop listening for key presses.

5. **Convert to PDF**:
   - Click **"Convert to PDF"** to combine all captured screenshots into a single PDF file.

### Option 3: Clean Mode

Deletes all screenshots in the `screenshots` folder.

```bash
screenshot-macro clean
```

- Use this mode to clear all previously captured screenshots.

## Project Structure

```
ScreenshotMacro/
├── README.md
├── main.py
├── requirements.txt
├── screenshots/             # Folder where screenshots are saved
├── setup.py
└── src/
    ├── __init__.py
    ├── constants.py         # Constants and path configurations
    ├── gui_setup.py         # Common GUI setup module
    ├── macro.py             # Macro mode class
    ├── utils.py             # Utility functions
    └── view.py              # View mode class
```

## Notes

- **MacOS Only**: These scripts rely on the `screencapture` command, which is only available on MacOS.
- **Screenshots Folder**: By default, screenshots are saved in the `screenshots` directory within the project.
- **PDF Output**: The combined PDF is saved in the project directory, with a filename like `1.pdf`.
- **Permissions**: You may need to grant screen recording permissions to the Python interpreter in your Mac's System Preferences under Security & Privacy.
