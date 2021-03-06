;; This gives us a simple moving triangle

(defparameter *gpu-array* nil)
(defparameter *vertex-stream* nil)
(defparameter *loop* 0.0)

(defsfun calc-offset ((a :float) (loop :float))
  (return (v! (tan (* (cos a) (+ (sin a) loop)))
              (cos  (+ (cos a) loop))
              0.0 0.0)))

(deffshader frag (&uniform (loop :float)) 
  (out output-color (v! (cos loop) (sin loop) 1.0 1.0)))

(defpipeline prog-1 ((position :vec4) &uniform (i :int) (loop :float))
  (:vertex (setf gl-position (+ position (calc-offset (float i) loop))))
  frag)

(defun draw (gstream)
  (setf *loop* (+ 0.004 *loop*))
  (gl:clear :color-buffer-bit)  
  (loop :for i :below 50 :do
     (let ((i (/ i 2.0)))
       (prog-1 gstream :i i :loop *loop*)))
  (gl:flush)
  (sdl:update-display))

(defun run-demo ()
  (cgl:clear-color 0.0 0.0 0.0 0.0)
  (cgl:viewport 0 0 640 480)
  (setf *gpu-array* (make-gpu-array (list (v!  0.0   0.2  0.0  1.0)
                                          (v! -0.2  -0.2  0.0  1.0)
                                          (v!  0.2  -0.2  0.0  1.0))
                                    :element-type :vec4
                                    :dimensions 3))
  (setf *vertex-stream* (make-vertex-stream *gpu-array*))
  (loop :until (find :quit-event (sdl:collect-event-types)) :do
     (cepl-utils:update-swank)
     (continuable (draw *vertex-stream*))))
