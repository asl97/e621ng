<template>
  <div class="upload-preview-container" :class="classes && finalPreviewClass">
    <div class="box-section background-red" v-show="overDims">
      One of the image dimensions is above the maximum allowed of 15,000px and will fail to upload.
    </div>
    <div v-if="!failed">
      <div class="upload-preview-dims">{{ previewDimensions }}</div>
      <div class="upload-preview-wrapper">
        <video
          v-if="data.isVideo"
          class="upload-preview-image"
          controls
          :src="finalPreviewUrl"
          ref="video"
          v-on:loadeddata="imageLoaded($event)"
          v-on:error="previewFailed()"
        ></video>
        <img
          v-else
          class="upload-preview-image"
          :src="finalPreviewUrl"
          referrerpolicy="no-referrer"
          ref="image"
          v-on:load="imageLoaded($event)"
          v-on:error="previewFailed()"
        />
        <canvas
          class="upload-preview-cropper"
          ref="canvas"
        ></canvas>
      </div>
      <div class="upload-preview-thumb-dims">{{ thumbnailDimensions }}</div>
    </div>
    <div v-else class="preview-fail">
      <p>The preview for this file failed to load. Please, double check that the URL you provided is correct.</p>
      Note that some sites intentionally prevent images they host from being displayed on other sites. The file can still be uploaded despite that.
    </div>
  </div>
</template>

<script>
import { data } from 'jquery';

const thumbNone = "data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==";
const handlePositions = [
  [[15, -5], [-5, -5], [-5, 15]],
  [[-15, -5], [5, -5], [5, 15]],
  [[15, 5], [-5, 5], [-5, -15]],
  [[-15, 5], [5, 5], [5, -15]],
];

export default {
  props: {
    classes: String,
    data: {
      validator: function(obj) {
        return typeof obj.isVideo === "boolean" && typeof obj.url === "string";
      }
    },
  },
  data() {
    return {
      heigth: 0,
      width: 0,
      overDims: false,
      failed: false,

      minWidth: 150,

      /** Selector position information */
      selector: {
        left: 0,
        top: 0,
        side: 0,
      },

      dragging: null,
      canvasRatio: 1,

      /** Current mouse position */
      mouse: {
        x: 0,
        y: 0,
      },

      /** Mouse position prior to movement */
      mouseOld: {
        x: 0,
        y: 0,
      },
      
    }
  },
  computed: {
    previewDimensions() {
      console.log("dims1", this.height, this.width);
      if (this.width > 1 && this.height > 1)
        return this.width + "×" + this.height;
      return "";
    },
    thumbnail() {
      return {
        left: Math.floor(this.selector.left / this.canvasRatio),
        top: Math.floor(this.selector.top / this.canvasRatio),
        side: Math.floor(this.selector.side / this.canvasRatio),
      };
    },
    thumbnailDimensions() {
      if (!this.isSelectorValid) return;
      return this.thumbnail.left + " / "
           + this.thumbnail.top + " / "
           + this.thumbnail.side;
    },
    isSelectorValid() {
      console.log("valid", this.selector.left, this.selector.top, this.selector.side);
      return this.selector.left >= 0 && this.selector.top >= 0 && this.selector.side >= 1;
    },
    finalPreviewUrl() {
      return this.data.url === "" ? thumbNone : this.data.url;
    },
    finalPreviewClass() {
      return this.data.url === "" ? "disabled" : "";
    },
  },
  mounted() {
    console.log("mounting");
    this.canvas = this.$refs.canvas;

    let resizeTimeout = 0;
    window.addEventListener("resize", () => {
      if(resizeTimeout) return;
      resizeTimeout = window.setTimeout(() => {
        this.resetCanvas();
        resizeTimeout = 0;
      }, 30);
    });

    this.canvas.addEventListener('mousedown', this.mouseDown, false);
    this.canvas.addEventListener('mouseup', this.mouseUp, false);
    this.canvas.addEventListener("mouseout", this.mouseUp, false);
    this.canvas.addEventListener("blur", this.mouseUp, false);

    let mouseMoveTimeout = 0;
    this.canvas.addEventListener("mousemove", (event) => {
      if(mouseMoveTimeout) return;
      mouseMoveTimeout = window.setTimeout(() => {
        this.mouseMove(event);
        mouseMoveTimeout = 0;
      }, 30);
    }, false);

    this.canvas.addEventListener('touchstart', this.mouseDown);
    this.canvas.addEventListener('touchend', this.mouseUp);

    this.canvas.addEventListener('touchmove', (event) => {
      if(mouseMoveTimeout) return;
      mouseMoveTimeout = window.setTimeout(() => {
        this.mouseMove(event);
        mouseMoveTimeout = 0;
      }, 30);
    });
  },
  watch: {
    data: function() {
      this.resetFilePreview();
      this.resetCanvas();
    }
  },
  methods: {
    resetCanvas() {
      console.log("resetting canvas");
      const subject = this.$refs.image;

      if(this.failed || !subject || !subject.height || !subject.width) {
        console.log("Aborting");
        this.canvas.height = this.canvas.width = 0;
        this.clearCanvas();
        return;
      }

      let oldThumbnail = this.thumbnail;
      this.canvasRatio = subject.height / this.height;
      console.log("ratio", subject.height, this.height, this.canvasRatio);

      console.log("canvas", subject.height, subject.width);
      this.canvas.width = subject.width;
      this.canvas.height = subject.height;

      if(this.isSelectorValid) {
        console.log("old", this.selector);
        console.log(oldThumbnail.side, this.canvasRatio, oldThumbnail.side * this.canvasRatio, this.canvas.height);
        this.selector.top = oldThumbnail.top * this.canvasRatio;
        this.selector.left = oldThumbnail.left * this.canvasRatio;
        this.selector.side = oldThumbnail.side * this.canvasRatio;
        console.log("fix", this.selector);
      } else {
        this.selector.top = 5;
        this.selector.left = 5;
        this.selector.side = Math.min(subject.width, subject.height) - 10;
      }

      this.drawRectInCanvas();
    },
    clearCanvas() {
      var ctx = this.canvas.getContext("2d");
      ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    },
    drawRectInCanvas() {
      var ctx = this.canvas.getContext("2d");
      ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

      ctx.beginPath();
      ctx.lineWidth = "3";
      ctx.fillStyle = "rgba(199, 87, 231, 0.2)";
      ctx.strokeStyle = "#c757e7";
      
      ctx.rect(this.selector.left, this.selector.top, this.selector.side, this.selector.side);
      ctx.fill();
      ctx.stroke();

      drawHandle(this.canvas, this.selector.left, this.selector.top, 0, this.dragging == 1);
      drawHandle(this.canvas, this.selector.left + this.selector.side, this.selector.top, 1, this.dragging == 2);
      drawHandle(this.canvas, this.selector.left, this.selector.top + this.selector.side, 2, this.dragging == 3);
      drawHandle(this.canvas, this.selector.left + this.selector.side, this.selector.top + this.selector.side, 3, this.dragging == 4);

      ctx.beginPath();
      ctx.font = "16px monospace";
      ctx.fillStyle = "#000000";
      ctx.fillText("█████████", this.selector.left + 16, this.selector.top + 16)

      ctx.fillStyle = "#ffd666";
      ctx.fillText("thumbnail", this.selector.left + 16, this.selector.top + 16);

      function drawHandle(canvas, x, y, position, highlight = false) {
        var ctx = canvas.getContext("2d");
        ctx.fillStyle = highlight ? "#fe6a64" : "#c757e7";
        ctx.beginPath();

        let coords = handlePositions[position];
        ctx.moveTo(x + coords[0][0], y + coords[0][1]);
        ctx.lineTo(x + coords[1][0], y + coords[1][1]);
        ctx.lineTo(x + coords[2][0], y + coords[2][1]);

        ctx.fill();
      }
    },

    updateMousePosition(event) {
      var clx, cly
      if (event.type == "touchstart" || event.type == "touchmove") {
        clx = event.touches[0].clientX;
        cly = event.touches[0].clientY;
      } else {
        clx = event.clientX;
        cly = event.clientY;
      }
      var boundingRect = this.canvas.getBoundingClientRect();
      this.mouse = {
        x: clx - boundingRect.left,
        y: cly - boundingRect.top
      };
    },

    mouseDown(event) {
      if(this.dragging !== null) return;
      this.updateMousePosition(event);

      if (isInBox(this.mouse.x, this.mouse.y, this.selector)){
        this.dragging = 0;
        this.mouseOld = this.mouse;
        // Falls through, in case of clicking on the circle inside the box
      }

      //   | 1  2
      // --|------
      // 0 | 1  2
      // 2 | 3  4
      let vertical, horizontal;

      if (isCloseEnough(this.mouse.y, this.selector.top)) vertical = 0;
      else if (isCloseEnough(this.mouse.y, this.selector.top + this.selector.side)) vertical = 2;
      else return;

      if (isCloseEnough(this.mouse.x, this.selector.left)) horizontal = 1;
      else if (isCloseEnough(this.mouse.x, this.selector.left + this.selector.side)) horizontal = 2;
      else return;

      this.dragging = vertical + horizontal;
      this.mouseOld = this.mouse;
      console.log("mouseDown", this.dragging);

      this.drawRectInCanvas();

      function isInBox(x, y, box) {
        return (x > box.left && x < (box.side + box.left)) && (y > box.top && y < (box.top + box.side));
      }

      function isCloseEnough(p1, p2) {
        return Math.abs(p1 - p2) < 20;
      }
    },
    mouseUp() {
      this.dragging = null;
      this.mouseOld = null;
      this.drawRectInCanvas();
      this.thumbnailDimensionsChanged();
    },
    mouseMove(event) {    
      this.updateMousePosition(event);
      if(this.dragging == null) return;

      event.preventDefault();
      event.stopPropagation();

      const diffX = this.mouse.x - this.mouseOld.x;
      const diffY = this.mouse.y - this.mouseOld.y;
      this.mouseOld = this.mouse;

      switch (this.dragging) {
        case 0: { // Entire box
          if (diffX) {
            this.selector.left += diffX;
            if (this.selector.left < 0) this.selector.left = 0;
            if (this.selector.left + this.selector.side > this.canvas.width)
              this.selector.left = this.canvas.width - this.selector.side;
          }

          if (diffY) {
            this.selector.top += diffY;
            if (this.selector.top < 0) this.selector.top = 0;
            if (this.selector.top + this.selector.side > this.canvas.height)
              this.selector.top = this.canvas.height - this.selector.side;
          }

          console.log("move", diffX, diffY);
          break;
        }
        case 1: { // Top left
          let newSide = this.selector.side + ((-diffX + -diffY) / 2);
          if(newSide / this.canvasRatio < this.minWidth)
            newSide = this.minWidth * this.canvasRatio;

          this.selector.left = this.selector.left + this.selector.side - newSide;
          this.selector.top = this.selector.side + this.selector.top - newSide;
          this.selector.side = newSide;

          console.log("resize 1", newSide);
          break;
        }
        case 2: { // Top right
          let newSide = this.selector.side + ((diffX + -diffY) / 2);
          if(newSide / this.canvasRatio < this.minWidth)
            newSide = this.minWidth * this.canvasRatio;
          
          this.selector.top = this.selector.side + this.selector.top - newSide;
          this.selector.side = newSide;

          console.log("resize 2", newSide);
          break;
        }
        case 3: { // Bottom left
          let newSide = this.selector.side + ((-diffX + diffY) / 2);
          if(newSide / this.canvasRatio < this.minWidth)
            newSide = this.minWidth * this.canvasRatio;

          this.selector.left = this.selector.left + this.selector.side - newSide;
          this.selector.side = newSide;

          console.log("resize 3", newSide);
          break;
        }
        case 4: { // Bottom right
          let newSide = this.selector.side + ((diffX + diffY) / 2);
          if(newSide / this.canvasRatio < this.minWidth)
            newSide = this.minWidth * this.canvasRatio;
          
          this.selector.side = newSide;

          console.log("resize 4", newSide);
          break;
        }
        default: {
          console.log("unknown");
        }
      }

      if(this.selector.left < 0) this.selector.left = 0;  // left boundary
      if(this.selector.top < 0) this.selector.top = 0;    // top boundary
      if(this.selector.left + this.selector.side > this.canvas.width)  // right boundary
        this.selector.side = this.canvas.width - this.selector.left;
      if(this.selector.top + this.selector.side > this.canvas.height)  // bottom boundary
        this.selector.side = this.canvas.height - this.selector.top;

      this.drawRectInCanvas();
    },

    thumbnailDimensionsChanged() {
      this.$emit("thumbnailDimensionsChanged", this.thumbnail);
    },

    imageLoaded(event) {
      console.log("image loaded");
      this.updateDimensions(event);
      this.resetCanvas();
      this.thumbnailDimensionsChanged();
    },

    updateDimensions(e) {
      const target = e.target;
      this.height = target.naturalHeight || target.videoHeight;
      this.width = target.naturalWidth || target.videoWidth;
      this.overDims = (this.height > 15000 || this.width > 15000);
    },
    resetFilePreview() {
      this.overDims = false;
      this.width = 0;
      this.height = 0;
      this.failed = false;
    },
    previewFailed() {
      this.failed = true;
    },
  }
};
</script>
