;; Raymarcher!

(defparameter *gpu-array* nil)
(defparameter *vertex-stream* nil)
(defparameter *loop* 0.0)

(defsfun sphere ((p :vec3) (r :float)) 
  (return (- (length (* rot p)) r)))

(defsfun box ((p :vec3) (b :vec3)) 
  (let ((d (- (abs (* rot p)) b)))
    (return (+ (min (max (x d) (max (y d) (z d))) 0.0)
               (length (max d 0.0))))))

(defvshader vs ((position :vec4))
  (setf gl-position position)
  (out posxy (swizzle position :xy)))

(deffshader fs ((posxy :vec2) &uniform (loop :float) (radius :float) 
                (fog-dist :float) (eye-pos :vec3) (rot :mat3))
  (let* ((eye-dir (normalize (v! (x posxy) (y posxy) 1.0)))
         (e eye-pos)
         (output (v! 0.0 0.0 0.0))
         (box-dim (v! 1.0 2.0 1.0)))
    (for (i 0) (< i 20) (++ i)
         (let ((d (box e box-dim)))
           (if (<= d 0.0) 
               (let ((norm (normalize (v! (- (box (+ e (v! 0.01 0.0 0.0)) box-dim)
                                             (box (- e (v! 0.01 0.0 0.0)) box-dim))
                                          (- (box (+ e (v! 0.0 0.01 0.0)) box-dim)
                                             (box (- e (v! 0.0 0.01 0.0)) box-dim))
                                          (- (box (+ e (v! 0.0 0.0 0.01)) box-dim)
                                             (box (- e (v! 0.0 0.0 0.01)) box-dim))))))
                 (setf output (v! (+ 0.3 (* 0.5 (y norm))) 
                                  0.0
                                  (+ 0.5 (* 0.2 (mix (y norm) (x norm)
                                                     (sin (* 1.0 loop))))) ))
                 (break)))
           (setf d (max d 0.01))
           (setf e (+ e (* eye-dir d)))))
    (out output-color (vec4 output 1.0))))

(defpipeline prog-1 ((position :vec4) &uniform (loop :float) (radius :float) 
                     (fog-dist :float) (eye-pos :vec3) (rot :mat3))
  vs fs)

(defun run-demo ()
  (cgl:clear-color 0.0 0.0 0.0 0.0)
  (cgl:viewport 0 0 640 480)
  (setf *gpu-array* (make-gpu-array (list (v! -1.0  -1.0  0.0  1.0)
                                          (v!  1.0  -1.0  0.0  1.0)
                                          (v!  1.0   1.0  0.0  1.0)
                                          (v!  1.0   1.0  0.0  1.0)
                                          (v! -1.0   1.0  0.0  1.0)
                                          (v! -1.0  -1.0  0.0  1.0))
                                    :element-type :vec4
                                    :dimensions 6))
  (setf *vertex-stream* (make-vertex-stream *gpu-array*))
  (loop :until (find :quit-event (sdl:collect-event-types)) :do
     (cepl-utils:update-swank)
     (continuable (draw *vertex-stream*))))

(defun draw (gstream)
  (setf *loop* (+ 0.01 *loop*))
  (gl:clear :color-buffer-bit)
  (prog-1 gstream :loop *loop* :radius 1.4 :fog-dist 8.0
          :eye-pos (v! -1.3 1.3 -5.0) :rot (m3:rotation-y (* 0.1 *loop*)))
  (gl:flush)
  (sdl:update-display))

