import os
import glob
import subprocess
from flask import Flask, request, redirect, url_for, render_template_string, flash
from werkzeug.utils import secure_filename
from PIL import Image

# Base directory for the app
BASE_DIR = os.path.dirname(__file__)
# Folder to store PNGs and for framebuffer display
UPLOAD_FOLDER = os.path.join(BASE_DIR, 'uploads')
DISPLAY_FILE = os.path.join(BASE_DIR, 'display.png')
ALLOWED_EXT = {'png'}
LAST_FILE = os.path.join(BASE_DIR, 'last.txt')
# Store last rotation
LAST_ROT = os.path.join(BASE_DIR, 'rotation.txt')

# Ensure the uploads folder exists
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.secret_key = 'replace_with_random_secret'

# HTML template with rotation option
TEMPLATE = '''
<!doctype html>
<title>Pi Image Control</title>
<h1>Upload a PNG</h1>
<form method="post" enctype="multipart/form-data" action="/upload">
  <input type="file" name="file" accept="image/png">
  <input type="submit" value="Upload">
</form>
{% with messages = get_flashed_messages() %}
  {% if messages %}
    <ul>{% for msg in messages %}<li>{{ msg }}</li>{% endfor %}</ul>
  {% endif %}
{% endwith %}
<hr>
<h1>Available Images</h1>
<form method="post" action="/display">
  {% for img in images %}
    <div>
      <input type="radio" id="{{ img }}" name="filename" value="{{ img }}" {% if img==current_file %}checked{% endif %}>
      <label for="{{ img }}">{{ img }}</label>
    </div>
  {% endfor %}
  <p>Rotation:
    <select name="rotate">
      {% for angle in [0,90,180,270] %}
        <option value="{{angle}}" {% if angle==current_rot %}selected{% endif %}>{{angle}}°</option>
      {% endfor %}
    </select>
  </p>
  <input type="submit" value="Show Selected">
</form>
<hr>
<form method="post" action="/purge" onsubmit="return confirm('Are you sure?');">
  <input type="submit" value="Purge All Images">
</form>
'''

def get_last_displayed():
    if os.path.exists(LAST_FILE):
        return open(LAST_FILE).read().strip()
    return None

def set_last_displayed(filename):
    with open(LAST_FILE, 'w') as f:
        f.write(filename)

def get_last_rotation():
    if os.path.exists(LAST_ROT):
        return int(open(LAST_ROT).read().strip())
    return 0

def set_last_rotation(angle):
    with open(LAST_ROT, 'w') as f:
        f.write(str(angle))

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.',1)[1].lower() in ALLOWED_EXT

@app.route('/')
def index():
    images = sorted([f for f in os.listdir(UPLOAD_FOLDER) if f.lower().endswith('.png')])
    current = get_last_displayed() or (images[0] if images else None)
    rot = get_last_rotation()
    return render_template_string(TEMPLATE, images=images, current_file=current, current_rot=rot)

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files.get('file')
    if not file or not allowed_file(file.filename):
        flash('Select a valid PNG')
        return redirect(url_for('index'))
    name = secure_filename(file.filename)
    file.save(os.path.join(UPLOAD_FOLDER, name))
    set_last_displayed(name)
    flash(f'Uploaded {name}')
    return redirect(url_for('index'))

def rotate_and_save(src, angle):
    # Open original and rotate
    img = Image.open(src)
    rotated = img.rotate(angle, expand=True)
    rotated.save(DISPLAY_FILE)
    return DISPLAY_FILE

@app.route('/display', methods=['POST'])
def display():
    sel = request.form.get('filename')
    angle = int(request.form.get('rotate',0))
    src_path = os.path.join(UPLOAD_FOLDER, sel)
    if not os.path.exists(src_path):
        flash('Image not found')
        return redirect(url_for('index'))
    set_last_displayed(sel)
    set_last_rotation(angle)
    # Rotate and save to display file
    display_path = rotate_and_save(src_path, angle)
    # Kill any existing display
    subprocess.run(['pkill', 'fbi'], stderr=subprocess.DEVNULL)
    subprocess.run(['chvt', '1'])
    # Show with fbi
    subprocess.run(['sudo', 'fbi', '-T', '1', '-d', '/dev/fb0', '-noverbose', '-a', display_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    flash(f'Displaying {sel} at {angle}°')
    return redirect(url_for('index'))

@app.route('/purge', methods=['POST'])
def purge():
    subprocess.run(['pkill', 'fbi'], stderr=subprocess.DEVNULL)
    for f in glob.glob(os.path.join(UPLOAD_FOLDER, '*.png')):
        os.remove(f)
    if os.path.exists(LAST_FILE): os.remove(LAST_FILE)
    if os.path.exists(LAST_ROT): os.remove(LAST_ROT)
    flash('All images purged')
    return redirect(url_for('index'))

if __name__=='__main__':
    # on startup
    pngs = sorted(glob.glob(os.path.join(UPLOAD_FOLDER,'*.png')))
    last = get_last_displayed()
    rot = get_last_rotation()
    to_show = last if last and os.path.exists(os.path.join(UPLOAD_FOLDER,last)) else (os.path.basename(pngs[0]) if pngs else None)
    if to_show:
        src = os.path.join(UPLOAD_FOLDER, to_show)
        display_path = rotate_and_save(src, rot)
        subprocess.run(['pkill', 'fbi'], stderr=subprocess.DEVNULL)
        subprocess.run(['chvt', '1'])
        subprocess.run(['sudo', 'fbi', '-T', '1', '-d', '/dev/fb0', '-noverbose', '-a', display_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    app.run(host='0.0.0.0', port=8000, use_reloader=False)
