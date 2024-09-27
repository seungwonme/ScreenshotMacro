# Screenshot Macro for MacOS

This repository contains Python scripts that automate the process of taking screenshots and converting them into a PDF. **These scripts are only compatible with MacOS**, as they rely on the `screencapture` command-line utility, which is native to Mac systems.

## Requirements

- MacOS (due to the usage of the `screencapture` command)
- Python 3.x

To install the required Python libraries, you can use:

```bash
pip install -r requirements.txt
```

## Usage

There are two versions of the code in this repository:

1. A single script that takes screenshots and immediately combines them into a PDF.
2. A split version that separates the screenshot-taking and PDF conversion into two distinct scripts.

### Option 1: Using the Single Script (`run.py`)

This script handles both the screenshot-taking process and the PDF conversion in one go.

1. Run the script:
   ```bash
   python run.py
   ```
2. Follow the on-screen instructions to set the screenshot area, number of repetitions, and delay between each screenshot.
3. The script will automatically save the screenshots and combine them into a PDF in the working directory.

### Option 2: Using the Split Scripts (`screenshot_macro.py` and `convert_to_pdf.py`)

In this option, the process is divided into two steps.

#### Step 1: Take Screenshots (`screenshot_macro.py`)

1. Run the screenshot script:
   ```bash
   python screenshot_macro.py
   ```
2. Follow the on-screen instructions to set the screenshot area, number of repetitions, and delay between each screenshot.
3. The screenshots will be saved in the `screenshot` folder within the project directory.

#### Step 2: Convert Screenshots to PDF (`convert_to_pdf.py`)

1. After taking the screenshots, run the conversion script:
   ```bash
   python convert_to_pdf.py
   ```
2. This will combine all `.png` files in the `screenshot` folder into a single PDF named `output.pdf` in the project directory.

## Notes

- **MacOS only**: These scripts rely on the `screencapture` command, which is only available on MacOS.
- The default screenshot files are stored in the `screenshot` folder, and the resulting PDF is named `output.pdf` unless modified in the script.
- Ensure that the `screenshot` folder contains only the images you wish to combine into the PDF.
